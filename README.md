# B1
B1 is a Lua 5.1 obfuscator that can only obfuscate Lua 5.1 but for now i change some things so it can also obfuscate luau files. I am unlikely to ever use this for production and is just a project for others and me to learn more about. The obfuscator uses Luac to compile code to bytecode, which the parser reads. It builds a VM using the parser's output and finally minifies the code using [luasrcdiet](https://github.com/jirutka/luasrcdiet).

## Usage
```
lua Main.lua <InputPath> <OutputPath>
```

### CLI flags
- `--constantprotection` – encrypts constants for stronger constant security. **(WIP)**
- `--minify` – minifies the output for smaller scripts.
- `--antitamper` – injects anti-tamper checks to detect script modification.  **(WIP)**
- `--encryptstrings` – encrypts all strings in the output.
- `--controlflowflattening` – flattens control flow for simple obfuscation hardening.
- `--debug` – enables debugging tools to help diagnose errors.
- `--luau` – converts luau syntax into normal lua to feed into compile
