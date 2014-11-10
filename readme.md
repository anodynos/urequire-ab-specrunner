# urequire-ab-specrunner

Automagically generates and runs Specs using mocha, chai & phantomjs after running a `lib` and a `specs` build in [uRequire](http://urequire.org) running on grunt.

# Introduction

Manually configuring `watch`, `mocha` tasks and phantomjs, requirejs/AMD & all their relative paths, configs, shims, HTMLs etc against each different build, can be a huge pain. You 'll find repeating your self too much, fiddling with what paths work and what breaks, instead of writing awesome libs and specs.

Here comes urequire-ab-specrunner, an `afterBuild`-er that is build around urequire's (>= v0.7) `afterBuild` facility: with a single declaration and no other configuration, it generates HTML and specs invocations for nodejs & browser and runs them each time you build!

It basically uses uRequire's `bundle` & `build` information already in the urequire config (and the materialized bundle & build) to do its magic. It relies on urequire auto discovery of dependencies paths (using bower and npm behind the scenes) and it automagically generates, configures and runs your specs against the lib using node's `mocha` and [`mocha-phantomjs`](https://github.com/metaskills/mocha-phantomjs) (which are assumed to be installed and working on your machine).

It works perfectly with watching through `grunt-contrib-watch`, which __you dont__ need to configure at all (but is assumed to be locally installed along grunt). The best parts is that because uRequire __really knows__ if your bundle sources __really changed__ (not just some white space or some comments changed in your javascript or coffeescript, but the actual AST) or if a build failed, *urequire-ab-specrunner* wont run the specs until the errors are resolved and only if sources really changed.

It even auto generates the SpecRunner HTML with the RequireJs config & paths (or depending on the templates used if AMD isn't available/needed it uses the `<script src='../../../tedious/paths/to/somedep.js'/>` that still respect the requirejs config's `shim`) and runs them!

## Usage

Assuming you already have some configs of your lib, for example `libUMD`, `libMin` etc and some for the specs against it, for example `spec`, All you 'll need is:

```coffeescript

  libUMD: {...}
  libMin: {...}
  spec:   {...}

  specRun:
    derive: ['spec']
    dependencies: paths: bower: true
    afterBuild: require('urequire-ab-specrunner')
```

and hit `$ grunt libUMD specRun` or `$ grunt libMin specRun` etc - just remember to invoke them in pairs of a `lib` build followed by a `spec` build. You can add the `afterBuild: require('urequire-ab-specrunner')` to `spec` so that all `specXXX` inherit it, and then hit `$ grunt libUMD specMin`.

Add a `watch: true` to either your `lib` or `spec` config (or both), and `watch`-ing starts automatically after the first successful build (it actually auto configures and invokes `grunt-contrib-watch`).

See [urequire-example](https://github.com/anodynos/urequire-example) for a full working example.

## Options

You can pass options by invoking

```
afterBuild: require('urequire-ab-specrunner').options({
    someOption: someValue })
```

and passing an options object. The actual options are :

### `injectCode` / `injectRaw`

You can add arbitrary code / HTML in the generated HTML, usually to setup globals or other things not covered by *urequire-ab-specrunner*. The code is injected before any other libraries are loaded, just after `mocha.js` & `chai.js` are loaded.

`injectCode` injects its content inside a `<script>` tag, while `injectRaw` injects the contents as it is in the HTML. You can use both, `injectCode` where comes 1st.

##### Example
```
  afterBuild: require('urequire-ab-specrunner').options({
    injectCode: """
      // test `noConflict()`: create a global that 'll be 'hijacked' by rootExports
      window.urequireExample = 'Old global `urequireExample`';
    """})
```

### `mochaSetup`

By default a `mocha.setup('bdd')` is called - you can pass a `String` or an `{}` to change that default:

##### Example
```
  mochaSetup: { ui: 'bdd', ignoreLeaks: false }
```

### `mochaOptions`

You can pass options to the `mocha` or `mocha-phantomjs` CLI executables - just note that not all options are supported on `mocha-phantomjs` - [check its docs](https://github.com/metaskills/mocha-phantomjs#usage).

##### Example
```
  mochaOptions: "-R dot -t 200"
```

### `globals`

By default `mocha.run().globals([...])` are automatically detected by your urequire config, locals, shims etc. You can add some of your own:

##### Example
```
   globals: ['someGlobal', 'anotherOne']
```        

### `runOnErrors`

By default its `false`, but you can change to `true` if you're impatient. 

### `specRunners`

There are 2 + 1 spec runners called `mocha-cli`, `mocha-phantomjs` and the +1 is `grunt-mocha`.
By default *urequire-ab-specrunner* runs only the first two (cause `grunt-mocha` is veeeery slow and not really needed) in these cases:

  * If your build's templates are anything but `nodejs` and `AMD`, both `mocha-cli`, `mocha-phantomjs` run (ie you automatically test on `nodejs` and `browser`).

  * If your build's templates are `nodejs` or `AMD`, specs run only on either `mocha-cli` or `mocha-phantomjs` (ie you test on either on `nodejs` or `browser`).

If you force it to use an incompatible one with your template (eg `AMD` on `mocha-cli`) it'll complain. Best left on default setting.

##### Example

```
    specRunners: ['mocha-cli', 'mocha-phantomjs']
```

which is the __soft default__, meaning it will uncomplainingly skip incompatible runtime tests (i.e `nodejs` template builds on `mocha-phantomjs`).

### `exec`

If `exec: truthy` it uses `require('child_process').exec` instead of `require('child_process').spawn` (the default).

Spawn is preferred cause it taps mocha output (and assertion failures) as its generated. Use it only if you get `ENOENT` problems while running `mocha` or `mocha-phantomjs` (which you shouldn't, even on windows).

### `tidy`

If `tidy: truthy` it uses [`htmltidy`](https://github.com/vavere/htmltidy) to beautify the resulted HTML. By default its off.

**Note that htmltidy has a couple of known [breaking issues](https://github.com/vavere/htmltidy/issues/17) especially on x64 linux distros [(spawn ENOENT)](https://github.com/vavere/htmltidy/issues/11) cause its just a nodejs wrapper to an outdated 32bit binary, but [there are workarounds](https://github.com/vavere/htmltidy/issues/11#issuecomment-62376405). Also its author considers it experimental on darwin (Mac).** 

### `debugLevel`

Prints debug info, goes from `0` (default) to `100`.

# License

The MIT License

Copyright (c) 2014 Agelos Pikoulas (agelos.pikoulas@gmail.com)

Permission is hereby granted, free of charge, to any person
obtaining a copy of this software and associated documentation
files (the "Software"), to deal in the Software without
restriction, including without limitation the rights to use,
copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the
Software is furnished to do so, subject to the following
conditions:

The above copyright notice and this permission notice shall be
included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
OTHER DEALINGS IN THE SOFTWARE.