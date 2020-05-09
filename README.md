## Some `Bash` coding conventions and good practices.

Coding conventions are... just conventions.
They help to have a little fun with scripting,
not to create new war/bias conversations.

Feel free to break the rules any time you can; it's important
that you will always love what you would have written
because scripts can be too fragile, too hard to maintain,
or so many people hate them...
And it's also important to have a consistent way in your scripts.

* [Naming and styles](#naming-and-styles)
  * [Tabs and Spaces](#tabs-and-spaces)
  * [Pipe](#pipe)
  * [Variable names](#variable-names)
  * [Function names](#function-names)
* [Error handling](#error-handling)
  * [Sending instructions](#sending-instructions)
  * [Pipe error handling](#pipe-error-handling)
  * [Catch up with $?](#catch-up-with-)
  * [Automatic error handling](#automatic-error-handling)
    * [Set -u](#set--u)
    * [Set -e](#set--e)
* [Techniques](#techniques)
  * [Keep that in mind](#keep-that-in-mind)
  * [A little tracing](#a-little-tracing)
  * [Making your script a library](#making-your-script-a-library)
  * [Quick self-doc](#quick-self-doc)
  * [No excuse](#no-excuse)
  * [Meta programming](#meta-programming)
  * [Removing with care](#removing-with-care)
  * [Shell or Python/Ruby/etc](#shell-or-pythonrubyetc)
* [Contributions](#contributions)
  * [Variable names for arrays](#variable-names-for-arrays)
* [Good lessons](#good-lessons)
* [Resources](#resources)
* [Author. License](#author-license)

## Naming and Styles

### Tabs and Spaces

Don't use `(smart-)`tabs. Replace a tab by two spaces.
Do not accept any trailing spaces.

Many editors can't and/or aren't configured to display the differences
between tabs and spaces. Another person editor is just not your editor.
Having spaces does virtually help a strange reader of your script.

### Pipe

There are `inline` pipe and `display` pipe.  Unless your pipe is too
short, please use `display` pipe to make things clear. For example,

    This is an inline pipe: "$(ls -la /foo/ | grep /bar/)"

    # The following pipe is of display form: every command is on
    # its own line.

    _foobar="$( \
      ls -la /foo/ \
      | grep /bar/ \
      | awk '{print $NF}')"

    _generate_long_lists \
    | while IFS= read -r  _line; do
        _do_something_fun
      done

When using `display` form, put pipe symbol (`|`) at the beginning of
of its statement. Don't put `|` at the end of a line, because it's the
job of the line end (`EOL`) character and line continuation (`\`).

### Variable names

A variable is named according to its scope.

* If a variable can be changed from its parent environment,
  it should be in uppercase; e.g, `THIS_IS_A_USER_VARIABLE`.
* Other variables are in lowercase, started by an underscore;
  e.g, `_this_is_a_variable`. The primary purpose of the underscore (`_`)
  is to create a natural distance between the dollar (`$`)
  and the name when the variable is used (e.g, `$_this_is_a_variable`).
  This makes your code more readable, esp. when there isn't color support
  on your source code viewer.
* Any local variables inside a function definition should be
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
makes your code unreadable. Put each `local` statement on its own line.

`FIXME`: Add flexibility support.

### Function names

Name of internal functions should be started by an underscore (`_`).
Use underscore (`_`) to glue verbs and nouns. Don't use camel form
(`ThisIsNotMyStyle`; use `this_is_my_style` instead.)

Use two underscores (`__`) to indicate some very internal methods aka
the ones should be used by other internal functions.

## Error handling

### Sending instructions

All errors should be sent to `STDERR`. Never send any error/warning message
to a`STDOUT` device. Never use `echo` directly to print your message;
use a wrapper instead (`warn`, `err`, `die`,...). For example,

    _warn() {
      echo >&2 ":: $*"
    }

    _die() {
      echo >&2 ":: $*"
      exit 1
    }

Do not handle error of another function. Each function should handle
error and/or error message by their own implementation, inside its own
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
      # do something

      if [[ $? -ge 1 ]]; then
        _error "${FUNCNAME[0]} has some internal error"
      fi
    }

    _my_def() {
      _foobar_call || return 1
    }

### Catch up with $?

`$?` is used to get the return code of the *last statement*.
To use it, please make sure you are not too late. The best way is to
save the variable to a local variable. For example,

    _do_something_critical
    local _ret="$?"
    # from now on, $? is zero, because the latest statement (assignment)
    # (always) returns zero.

    _do_something_terrible
    echo "done"
    if [[ $? -ge 1 ]]; then
      # Bash will never reach here. Because "echo" has returned zero.
    fi

`$?` is very useful. But don't trust it.

Please don't use `$?` with `set -e` ;)

### Pipe error handling

Pipe stores its components' return codes in the `PIPESTATUS` array.
This variable can be used only *ONCE* in the sub-`{shell,process}`
followed the pipe. Be sure you catch it up!

    echo test | fail_command | something_else
    local _ret_pipe=( "${PIPESTATUS[@]}" )
    # from here, `PIPESTATUS` is not available anymore

When this `_ret_pipe` array contains something other than zero,
you should check if some pipe component has failed. For example,

    # Note:
    #   This function only works when it is invoked
    #   immediately after a pipe statement.
    _is_good_pipe() {
      echo "${PIPESTATUS[@]}" | grep -qE "^[0 ]+$"
    }

    _do_something | _do_something_else | _do_anything
    _is_good_pipe \
    || {
      echo >&2 ":: Unable to do something"
    }

### Automatic error handling

#### Set -u

Always use `set -u` to make sure you won't use any undeclared variable.
This saves you from a lot of headaches and critical bugs.

Because `set -u` can't help when a variable is declared and set to empty
value, don't trust it twice.

It's recommended to emphasize the needs of your variables before your
script actually starts. In the following example, the script just stops
when `SOME_VARIABLE` or `OTHER_VARIABLE` is not defined; these checks
are done just before any execution of the main routine(s).

```
: a lot of method definitions

set -u
: "${SOME_VARIABLE}"
: "${OTHER_VARIABLE}"

: your main routine
```

#### Set -e

Use `set -e` if your script is being used for your own business.

Be **careful** when shipping `set -e` script to the world. It can simply
break a lot of games. And sometimes you will shoot yourself in the foot.
If possible please have an option for user choice.

Let's see

    set -e
    _do_some_critical_check

    if [[ $? -ge 1 ]]; then
      echo "Oh, you will never see this line."
    fi

If `_do_some_critical_check` fails, the script just exits and the following
code is just skipped without any notice. Too bad, right? The code above
can be refactored as below

    set -e
    if _do_some_critical_check; then
      echo "Oh, it's better now"
    fi
    echo "Oh, you will always see this line."

Now, if you expect to stop the script when `_do_some_critical_check` fails
(it's the purpose of `set -e`, right?), these lines don't help. Why?
Because `set -e` doesn't work when being used with `if`. Confused?
Okay, these lines are the correct one

    set -e
    if _do_some_critical_check; then
      echo "Oh, it's better now"
    else
      echo "Something wrong we have to stop here"
      exit 1 # or return 1
    fi

`set -e` doesn't help to improve your code: it just forces you to work hard,
doesn't it?

Another example, in effect of `set -e`:

    (false && true); echo not here

prints nothing, while:

    { false && true; }; echo here

prints `here`.

The result is varied with different shells or even different versions of the same shell.

In general, don't rely on `set -e` and do proper error handling instead.

For more details about `set -e`, please read

* http://mywiki.wooledge.org/BashFAQ/105/Answers
* [When Bash scripts bite](https://news.ycombinator.com/item?id=14321213)

## Techniques

### Keep that in mind

There are lot of shell scripts that don't come with (unit)tests.
It's just not very easy to write tests. Please keep that in mind:
Writing shell scripts is more about dealing with runtime and side effects.

It's very hard to refactor shell scripts.
Be prepared, and don't hate bash/shell scripts too much ;)

### A little tracing

It would be very helpful if you can show in your script logs some tracing
information of the being-invoked function/method.

`Bash` has two jiffy variables `LINENO` and `FUNCNAME` that can help.
While it's easy to understand `LINENO`, `FUNCNAME` is a little complex.
It is an array of `chained` functions. Let's look at the following example

```
funcA() {
  log "This is A"
}

funcB() {
  log "This is B"
  funcA
}

funcC() {
  log "This is C"
  funcB
}

: Now, we call funcC

funcC
```

In this example, we have a chain: `funcC -> funcB -> funcA`.
Inside `funcA`, the runtime expands `FUNCNAME` to

```
FUNCNAME=(funcA funcB funcC)
```

The first item of the array is the method per-se (`funcA`),
and the next one is the one who instructs `funcA` (it is `funcB`).

So, how can this help? Let's define a powerful `log` function

```
log() {
  echo "(LOGGING) ${FUNCNAME[1]:-unknown}: *"
}
```

You can use this little `log` method everywhere, for example, when `funcB`
is invoked, it will print

```
LOGGING funcB: This is B
```

### Making your script a library

First thing first: Use `function` if possible. Instead of writting
some direct instructions in your script, you have a wrapper for them.
This is not good

    : do something cool
    : do something great

Having them in a function is better

    _default_tasks() {
      : do something cool
      : do something great
    }

Now in the very last lines of you script, you can execute them

    case "${@:-}" in
    ":")  echo "File included." ;;
    "")   _default_tasks        ;;
    esac

From other script you can include the script easily without executing
any code:

    # from other script
    source "/path/to_the_previous_script.sh" ":"

(When being invoked without any argument the `_default_tasks` is called.)

By advancing this simple technique, you have more options to debug
your script and/or change your script behavior.

### Quick self-doc

It's possible to generate beautiful self documentation by using `grep`,
as in the following example. You define a strict format and `grep` them:

    _func_1() { #public: Some quick introduction
      :
    }

    _func_2() { #public: Some other tasks
      :
    }

    _quick_help() {
      LANG=en_US.UTF_8
      grep -E '^_.+ #public' "$0" \
      | sed -e 's|() { #public: |☠|g' \
      | column -s"☠" -t \
      | sort
    }

When you execute `_quick_help`, the output is as below

    _func_1    Some quick introduction
    _func_2    Some other tasks

### No excuse

When someone tells you to do something, you may blindly do as said,
or you would think twice then raise your white flag.

Similarly, you should give your script a white flag. A backup script
can't be executed on any workstation. A clean up job can't silently
send `rm` commands in any directory. Critical mission script should

* exit immediately without doing anything if argument list is empty;
* exit if basic constraints are not established.

Keep this in mind. Always.

### Meta programming

`Bash` has a very powerful feature that you may have known:
It's very trivial to get definition of a defined method. For example,

    my_func() {
      echo "This is my function`"
    }

    echo "The definition of my_func"
    declare -f my_func

    # <snip>

Why is this important? Your program manipulates them. It's up to your
imagination.

For example, send a local function to remote and excute them via `ssh`

    {
      declare -f my_func    # send function definition
      echo "my_func"        # execution instruction
    } \
    | ssh some_server

This will help your program and script readable especially when you
have to send a lot of instructions via `ssh`. Please note `ssh` session
will miss interactive input stream though.

### Removing with care

It's hard to remove files and directories **correctly**.
Please consider to use `rm` with `backup` options. If you use some
variables in your `rm` arguments, you may want to make them immutable.

    export _temporary_file=/path/to/some/file/
    readonly _temporary_file
    # <snip>
    rm -fv "$_temporary_file"

### Shell or Python/Ruby/etc

In many situations you may have to answer to yourself whether you have
to use `Bash` and/or `Ruby/Python/Go/etc`.

One significant factor is that `Bash` doesn't have a good memory.
That means if you have a bunch of data (in any format) you probably
reload them every time you want to extract some portion from them.
This really makes your script slow and buggy. When your script
needs to interpret any kind of data, it's a good idea to move forward
and rewrite the script in another language, `Ruby/Python/Golang/...`.

Anyway, probably you can't deny to ignore `Bash`:
it's still very popular and many services are woken up by some shell things.
Keep learning some basic things and you will never have to say sorry.
Before thinking of switching to Python/Ruby/Golang, please consider
to write better Bash scripts first ;)

## Contributions

### Variable names for arrays

In #7, Cristofer Fuentes suggests to use special names for arrays.
Personally I don't follow this way, because I always try to avoid
to use Bash array (and/or associative arrays), and in Bash
per-se there are quite a lot of confusion (e.g, `LINENO` is a string,
`FUNCNAME` is array, `BASH_VERSION` is ... another array.)

However, if your script has to use some array, it's also possible to
have special name for them. E.g,

```
declare -A DEPLOYMENTS
DEPLOYMENTS["the1st"]="foo"
DEPLOYMENTS["the2nd"]="bar"
```

As there are two types of arrays, you may need to enforce a better name

```
declare -A MAP_DEPLOYMENTS
```

Well, it's just a reflection of some idea from another language;)

## Good lessons

See also in `LESSONS.md` (https://github.com/icy/bash-coding-style/blob/master/LESSONS.md).

## Resources

* [Anybody can write good bash with a little effort](https://blog.yossarian.net/2020/01/23/Anybody-can-write-good-bash-with-a-little-effort)
* [Google - Shell Style Guide](https://google.github.io/styleguide/shell.xml)
* [Defensive Bash programming](https://news.ycombinator.com/item?id=7815190)
* [Shellcheck](https://github.com/koalaman/shellcheck)

## Authors. License

The original author is Anh K. Huynh and the original work was part of
[`TheSLinux`](http://theslinux.org/doc/bash/coding_style/).

A few contributors have been helped to fix errors and improve the style.
They are also the authors.

The work is released under a MIT license.
