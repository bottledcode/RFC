# PHP RFC: Function Autoloading v4

* Version: 1.0
* Date: 2024-08-15
* Author: Robert Landers, landers.robert@gmail.com
* Status: Under Discussion (or Accepted or Declined)
* First Published at: <http://wiki.php.net/rfc/function_autoloading4>

## Introduction

The topic of supporting function autoloading was brought up many times in the past, this RFC introduces a potential
implementation which would be consistent with what we have for autoloading classes.

## Proposal

The suggested change would be pretty straightforward and backwards-compatible:

1. Add two new constants to spl: SPL_AUTOLOAD_CLASS, SPL_AUTOLOAD_FUNCTION.
2. Add a fourth optional parameter for spl_autoload_register, with a default value of SPL_AUTOLOAD_CLASS.
3. The type for the missing token should also be passed to the $autoload_function callback as a second param. (e.g.,
   SPL_AUTOLOAD_CLASS for classes, SPL_AUTOLOAD_FUNCTION for functions)
4. Change the current class autoloading to only call the autoloaders which match with the SPL_AUTOLOAD_CLASS types.
5. Add the function autoloading to only call the autoloaders which match with the SPL_AUTOLOAD_FUNCTION types.

There won’t be any changes to the current autoloading mechanism when it comes to classes.
However, if a function

1. is called in a fully qualified form (e.g., a `use` statement or `\` prefix is used)
2. is not defined
3. and an autoloader is registered with the SPL_AUTOLOAD_FUNCTION type

then the autoloader will be called with the function name as the first parameter (with the initial slash removed) and
SPL_AUTOLOAD_FUNCTION as the second parameter.

However, if a function

1. is called in an unqualified form (e.g., `strlen()`)
2. is not defined locally or globally
3. and an autoloader is registered with the SPL_AUTOLOAD_FUNCTION type

then the autoloader will be called with the current namespace prepended to the function name.
If the autoloader chooses to look up the "basename" of the function, it may do so.

Example `PSR-4-style` (one function per file) function autoloader: 

```php
<?php

spl_autoload_register(function ($function, $type) {
    if ($type === SPL_AUTOLOAD_FUNCTION) {
        $function = str_replace('\\', DIRECTORY_SEPARATOR, $function);
        $file = __DIR__ . '/functions/' . $function . '.php';

        if (file_exists($file)) {
            require $file;
        }
    }
}, false, false, SPL_AUTOLOAD_FUNCTION);
```

## Backward Incompatible Changes

There are no backward incompatible changes.

## Proposed PHP Version(s)

8.5 or later.

## RFC Impact

### To Opcache

To be determined.

### New Constants

Two new constants will be added to the SPL extension: SPL_AUTOLOAD_CLASS, SPL_AUTOLOAD_FUNCTION.

## Open Issues

To be determined.

## Future Scope

Potentially, constants and stream wrappers can be added in a similar fashion.

## Proposed Voting Choices

<doodle title="Implement Function Autoloading v4, as described" auth="withinboredom" voteType="single" closed="true" closeon="2022-01-01T00:00:00Z">
   * Yes
   * No
</doodle>

## Patches and Tests

Not yet.

## Implementation

After the project is implemented, this section should contain - the
version(s) it was merged into - a link to the git commit(s) - a link to
the PHP manual entry for the feature - a link to the language
specification section (if any)

## References


- [autofunc](https://wiki.php.net/rfc/autofunc): This heavily influenced this RFC. (declined in 2011)
- [function_autoloading](https://wiki.php.net/rfc/function_autoloading): This RFC was declined in 2011.
- [function_autoloading_v2](https://wiki.php.net/rfc/function_autoloading2): This RFC was declined in 2012.

Thank you for all of those that contributed to the discussions back then. I hope that this RFC will be successful.

## Rejected Features

Keep this updated with features that were discussed on the mail lists.
