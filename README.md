
## Description

A Bash coding style.

The Vietnamese version can be found here
  http://theslinux.org/doc/bash/coding_style/

The English version is coming.

## Tabs and Spaces

Never use `(smart-)`tabs. Replace a tab by two spaces.

Do not accept any trailing spaces.

## Pipe

There are `inline` pipe and `display` pipe.  Unless your pipe is too
short, please use `display` pipe to make things clear.

Example

    This is an inline pipe: "$(ls -la /foo/ | grep /bar/)"

    # The following pipe is of display form: every command is on
    # its own line.

    _foobar="$( \
      ls -la /foo/ \
      | grep /bar/ \
      | awk '{print $NF}')"

When using `display` pipe, put pipe symbol (`|`) at the begining of
of pipe component. Never put `|` at the end of a line.

## Variable names

A variable is named according to its scope.

* If a variable can be changed from its parent environment,
  it should be in uppercase; e.g, `THIS_IS_A_USER_VARIABLE`.
* Other variables are in lowercase, started by an underscore;
  e.g, `_this_is_a_variable`.
* Any local variables inside a function definition must be
  declared with a `local` statement.

Example

    # The following variable can be provided by user at run time.
    D_ROOT="${D_ROOT:-}"

    # All variables inside `_my_def` are declared with `local` statement.
    _my_def() {
      local _d_tmp="/tmp/"
      local _f_a=
      local _f_b=

      # This is good, but it's quite a mess
      local _f_x= _f_y=
    }

Though `local` statement can declare multiple variables, that way
make your code unreadable. Put each `local` statement on its own line.

## Function names

Name of internal functions should be started with an underscore.
Use underscore (`_`) to glue verbs and nouns. Don't use camel form
(`ThisIsBad`; use `this_is_not_bad` instead.)

## Error handling

All errors should be sent to `STDERR`. Never send any error/warning message
to a`STDOUT` device. Never use `echo` directly to print your message;
use a wrapper instead (`warn`, `err`, `die`,...)

Do not handle error of another function. Each function should handle
error and/or error message by their own implement, inside its own
definition.

    _my_def() {
      _foobar_call

      if [[ $? -ge 1 ]]; then
        echo >&2 "_foobar_call has some error"
        _error "_foobar_call has some error"
        return 1
      fi
    }

In the above example, `_my_def` is trying to handle error for `_foobar_call`.
That's not a good idea. Use the following code instead

    _foobar_call() {

      if [[ $? -ge 1 ]]; then
        _error "$FUNCNAME has some internal error"
      fi
    }

    _my_def() {
      _foobar_call || return 1
    }
