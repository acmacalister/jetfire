# Contribution guidelines for Jetfire

## General Guidelines

- **Min iOS SDK**: 7
- **Language**: Objective-C. If you want to code Swift, do it in [Starscream](https://github.com/daltoniam/starscream). Swift code will be lovingly rejected, but rejected nonetheless.

## Style Guide

#### Base style:

Please add new code to this project based on the following style guidelines:

- [Apple's Coding Guidelines for Cocoa](https://developer.apple.com/library/mac/documentation/Cocoa/Conceptual/CodingGuidelines/CodingGuidelines.html)
- [NYTimes Objective C Style Guidelines](https://github.com/NYTimes/objective-c-style-guide)

Among other things, these guidelines call for:

- Open braces on the same line; close braces on their own line
- Always using braces for 'if' statements, even with single-liners
- No spaces in method signatures except after the scope (-/+) and between parameter segments
- Use dot-notation, not `setXXX:`, for properties (e.g. self.enabled = YES)
- Asterisk should touch variable name, not type (e.g. NSString *myString)
- Prefer `static const` declarations over `#define` for numeric and string constants
- Prefer private properties to ‘naked’ instance variables wherever possible
- Prefer CGGeometry methods to direct access of CGRect struct
- Use objective-c literal syntax whenever possible
    - `myArray[2]` over `[myArray objectAtIndex:2]`
    - `myDict[key]` over `[myDict objectForKey:key]`
- Avoid specifying values that are identical to defaults.
    - `NSString *str = nil;` is identical to `NSString *str;` under ARC

Write the least amount of code possible to accomplish a task while maintaining excellent readability.

#### Additions:

- Prefix all constants with `kJFR`
- Prefix all class names with `JFR`
- Group related methods with `#pragma mark -`
- Where possible, put class delegate decorators on a private extension in the .m file (e.g.\<UIScrollViewDelegate\>)

## Pull Requests and Code Reviews

No tests, no merge.

#### Submit the request:

- *Title*: Use your best judgement here. We trust you.
- *Description*: Write what your new feature does, or which bugs you're trying to fix. Make sure that all bugs listed name their respective tickets.
    - ***BONUS***: Reviewers and testers *love* when you include steps to take to prove you've fixed the bug.
 
#### Annotate the request:

- Use inline comments (in the "Files Changed" tab) to make notes about any "*Key Areas*" in the request. Examples of "*key areas*" include:
    - Non-obvious changes to conditionals/code-forks
    - Changes to user interaction code
    - Things you are unsure about the safety/status of (this is totally fine! Pull requests are a great area to ask questions that the broader team can glance at in the context of a larger change).

