import Foundation

// Running the tests:
//   - Xcode, or any Linux toolchain:   swift test            (XCTest)
//   - macOS with only the Command Line Tools (no XCTest), Swift 6+:
//       F=/Library/Developer/CommandLineTools/Library/Developer/Frameworks
//       swift test -Xswiftc -F -Xswiftc $F -Xlinker -rpath -Xlinker $F \
//         -Xlinker -rpath -Xlinker /Library/Developer/CommandLineTools/Library/Developer/usr/lib
//     (Swift Testing, which SwiftPM does not find there on its own.)
#if canImport(XCTest)
import XCTest
#elseif canImport(Testing)
import Testing
#else
#error("The tests need XCTest or Swift Testing; see the note at the top of TestSupport.swift.")
#endif

/// Framework-neutral assertions, so every case runs under XCTest (Linux
/// toolchains, Xcode) and under Swift Testing (Command Line Tools) unchanged.
struct TestFailure: Error, CustomStringConvertible {
    let description: String
}

func fail(_ message: String, file: StaticString = #filePath, line: UInt = #line, column: Int = #column) {
    #if canImport(XCTest)
    XCTFail(message, file: file, line: line)
    #else
    Issue.record(
        Comment(rawValue: message),
        sourceLocation: SourceLocation(fileID: "MisarDevTests/\(file)", filePath: "\(file)", line: Int(line), column: column)
    )
    #endif
}

func expectEqual<T: Equatable>(
    _ actual: @autoclosure () throws -> T,
    _ expected: @autoclosure () throws -> T,
    _ message: String = "",
    file: StaticString = #filePath, line: UInt = #line, column: Int = #column
) rethrows {
    let a = try actual()
    let e = try expected()
    if a != e { fail("\(a) is not equal to \(e)\(message.isEmpty ? "" : " — \(message)")", file: file, line: line, column: column) }
}

func expectTrue(
    _ condition: @autoclosure () throws -> Bool,
    _ message: String = "",
    file: StaticString = #filePath, line: UInt = #line, column: Int = #column
) rethrows {
    if try !condition() { fail("expected true\(message.isEmpty ? "" : " — \(message)")", file: file, line: line, column: column) }
}

func unwrap<T>(_ value: T?, file: StaticString = #filePath, line: UInt = #line, column: Int = #column) throws -> T {
    guard let value else {
        fail("unexpected nil", file: file, line: line, column: column)
        throw TestFailure(description: "unexpected nil at \(file):\(line)")
    }
    return value
}
