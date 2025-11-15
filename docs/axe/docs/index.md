<center>
<img src="assets/axe.png" alt="Axe Logo" width="50%">
</center>

Axe is a system programming language that aims to be simple and easy to learn, while still being powerful and efficient.

It aims to be a language that can be used for both system programming and application development, moreover, the language is intentionally minimal to avoid bloat and unnecessary complexity.

To provide a quick overview of the language, here is the simple hello world program:

```axe
main {
    println "Hello, world";
}
```

To compile and run the program, use the following command:

```bash
axe hello.axe
```

This will generate an executable, that can then be run with either `./hello` or `hello.exe` depending on the platform.

If for example you want to take commandline arguments and greet whoever passed it, you can do the following:

```axe
use stdlib/os(
    get_cmdline_args
);

main {
    print "Hello, ";
    print get_cmdline_args()[1];
}
```

