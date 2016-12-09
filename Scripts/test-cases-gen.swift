#!/usr/bin/env xcrun --sdk macosx swift

import Foundation

fileprivate extension String {
  func range(from nsRange: NSRange) -> Range<String.Index>? {
    guard
      let from16 = utf16.index(utf16.startIndex, offsetBy: nsRange.location, limitedBy: utf16.endIndex),
      let to16 = utf16.index(from16, offsetBy: nsRange.length, limitedBy: utf16.endIndex),
      let from = String.Index(from16, within: self),
      let to = String.Index(to16, within: self)
    else { return nil }

    return from ..< to
  }
}

fileprivate func resolveFinderAlias(path: String) -> String? {
  let fUrl = URL(fileURLWithPath: path)
  var targetPath: String? = nil

  do {
    // Get information about the file alias.
    // If the file is not an alias files, an exception is thrown
    // and execution continues in the catch clause.
    let data = try URL.bookmarkData(withContentsOf: fUrl)
    // .pathKey contains the target path.
    let rv = URL.resourceValues(forKeys: [.pathKey],
                                fromBookmarkData: data)
    targetPath = rv?.path
  } catch {
    // We know that the input path exists, but treating it as an alias
    // file failed, so we assume it's not an alias file and return its
    // *own* full path.
    targetPath = fUrl.path
  }

  return targetPath
}

internal struct TestCaseParser {

  private struct Pattern {
    static let testCaseName: String = "\\w*\\s+(\\w*)\\s*:\\s*XCTestCase"
    static let testName: String = "func\\s+(test\\w+)\\("
  }

  typealias TestCase = (String, [String])

  private let url: URL

  init(url: URL) {
    self.url = url
  }

  func parse() throws -> TestCase? {
    do {
      guard let testCaseName = try parseTestCaseName() else {
        return nil
      }

      return (testCaseName, try parseTestsNames())
    } catch let error {
      throw error
    }
  }

  static func parse(directoryAtURL url: URL) throws -> [TestCase] {
    let fileManager = FileManager.default
    let directoryEnumerator = fileManager
      .enumerator(at: url, includingPropertiesForKeys: [], options: [], errorHandler: nil)

    do {
      let testsCases = try directoryEnumerator?
        .flatMap { object -> TestCase? in
          guard
            let url = object as? URL,
            url.absoluteString.hasSuffix(".swift") else {
              return nil
          }

          do {
            let parser = TestCaseParser(url: url)

            guard let testCase = try parser.parse() else {
              return nil
            }

            return testCase
          } catch let error {
            throw error
          }
      }
      
      return testsCases ?? []
    } catch let error {
      throw error
    }
  }

  private func parseTestCaseName() throws -> String? {
    do {
      let contents = try String(contentsOf: url)
      
      let regex = try NSRegularExpression(pattern: Pattern.testCaseName)
      let matches = regex.matches(in: contents,
                                  range: NSRange(location: 0, length: contents.characters.count))
      
      return matches
        .first
        .flatMap { contents.range(from: $0.rangeAt(1)) }
        .flatMap { contents.substring(with: $0) }
    } catch let error {
      throw error
    }
  }

  private func parseTestsNames() throws -> [String] {
    do {
      let contents = try String(contentsOf: url)

      let regex = try NSRegularExpression(pattern: Pattern.testName)
      let matches = regex.matches(in: contents,
                                  range: NSRange(location: 0, length: contents.characters.count))

      return matches
        .flatMap { contents.range(from: $0.rangeAt(1)) }
        .flatMap { contents.substring(with: $0) }
    } catch let error {
      throw error
    }
  }
}

internal struct TestCasesGenerator {
  private static func spaces(forLevel level: Int) -> String {
    return String(repeating:" ", count: 2 * level)
  }
  
  static func generate(from testCases: [TestCaseParser.TestCase], level: Int) -> String {
    let testCasesString = testCases
      .map { testCase -> String in
        let testNamesString = testCase.1
          .map { testName in
            let spaces = self.spaces(forLevel: level + 3)
            
            return "\(spaces)(\"\(testName)\", \(testCase.0).\(testName)),\n"
          }
        .reduce("", +)

        let spaces = self.spaces(forLevel: level + 2)

        return
          "\(spaces)testCase([\n" +
          "\(testNamesString)" +
          "\(spaces)]),\n"
      }
      .reduce("", +)

    let spacesL0 = self.spaces(forLevel: level)
    let spacesL1 = self.spaces(forLevel: level + 1)

    return
      "//\n" +
      "//  automatically generated\n\n" +
      "//  Copyright (C) Microsoft. All rights reserved.\n" +
      "//  Licensed under the MIT license. " +
      "See LICENSE.txt file in the project root for full license information.\n" +
      "//\n\n" +
      "import SwiftXCTest\n" +
      "\n" +
      "public struct ThaliCoreTests {\n" +
      "\(spacesL0)public static var allTests: [XCTestCaseEntry] {\n" +
      "\(spacesL1)return [\n" +
      "\(testCasesString)" +
      "\(spacesL1)]\n" +
      "\(spacesL0)}\n" +
      "}\n"
  }
}

func main() {

  let droppedArguments = CommandLine.arguments.dropFirst()
  let path = droppedArguments[1]
  let outputPath = droppedArguments[2]

  guard
    let resolvedPath = resolveFinderAlias(path: path),
    let resolvedURL = URL(string: resolvedPath),
    let resolvedOutputPath = resolveFinderAlias(path: outputPath)
  else {
    return
  }

  let resolvedOutputURL = URL(fileURLWithPath: resolvedOutputPath)

  do {
    let testCases = try TestCaseParser.parse(directoryAtURL: resolvedURL)
    let testCasesString = TestCasesGenerator.generate(from: testCases, level: 1)

    try testCasesString.write(to: resolvedOutputURL, atomically: true, encoding: .utf8)
  } catch let error {
    print(error)
  }
}

main()
