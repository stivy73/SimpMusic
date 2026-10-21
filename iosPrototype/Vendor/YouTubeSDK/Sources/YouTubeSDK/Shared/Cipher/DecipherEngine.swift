//
//  DecipherEngine.swift
//  YouTubeSDK
//
//  Created by Aarav Gupta on 01/01/26.
//

import Foundation
import JavaScriptCore

class DecipherEngine {
    let context = JSContext()!
    
    private var decipherFunctionName: String?
    
    /// Loads the script and prepares the environment
    func loadCipherScript(_ script: String) throws {
        // 1. Evaluate the WHOLE script first (so all variables exist)
        // This puts 'base.js' into memory.
        context.evaluateScript(script)
        
        // 2. Find the Entry Point Function name
        // Regex Explanation:
        // [a-zA-Z0-9_$]+  -> Find a variable name (e.g. "Go")
        // \s*=\s*function\(a\) -> That is assigned a function taking 'a'
        // \{\s*a=a\.split\(""\) -> That immediately splits 'a'
        let pattern = #"([a-zA-Z0-9_$]+)\s*=\s*function\([a-zA-Z0-9_$]+\)\s*\{\s*[a-zA-Z0-9_$]+\s*=\s*[a-zA-Z0-9_$]+\.split\(""[\s\S]*?\}"#
        
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: script, range: NSRange(script.startIndex..., in: script)),
              let range = Range(match.range(at: 1), in: script) else {
            print("DECIPHER ENGINE: Couldn't find decipher function")
            throw URLError(.resourceUnavailable)
        }
        
        let functionName = String(script[range])
        self.decipherFunctionName = functionName
        print("DECIPHER ENGINE: LOCKED IN and founc function '\(functionName)'")
    }
    
    /// Unlocks a signature
    func decipher(signature: String) throws -> String {
        // We call the decipher function (we have to find its name first)
        // This is the tricky part: Finding the function name.
        // It usually looks like:  a.b(sig)
        guard let functionName = decipherFunctionName else {
            throw URLError(.userAuthenticationRequired)
        }
        
        // Call the JS Function from Swift
        // "Go('Ag82xb...')"
        let result = context.evaluateScript("\(functionName)'\(signature)'")
        
        if let decrypted = result?.toString(), !decrypted.isEmpty, decrypted != "undefined" {
            return decrypted
        } else {
            throw URLError(.cannotDecodeRawData)
        }
    }
}
