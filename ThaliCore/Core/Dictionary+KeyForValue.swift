//
//  Thali CordovaPlugin
//  String+KeyForValue.swift
//
//  Copyright (C) Microsoft. All rights reserved.
//  Licensed under the MIT license.
//  See LICENSE.txt file in the project root for full license information.
//

// MARK: Find key for value in Dictionary
extension Dictionary where Value: Equatable {

  func key(for value: Value) -> Key? {
    return self.filter { dictionaryKey, dictionaryValue in
                  dictionaryValue == value
                }
               .map { dictionaryKey, dictionaryValue in
                  dictionaryKey.0
                }
               .first
           ?? nil
  }
}
