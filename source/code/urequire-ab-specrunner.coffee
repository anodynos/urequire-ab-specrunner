minUrequireVersion = "0.7.0-beta6"

_ = (_B = require 'uberscore')._
l = new _B.Logger 'urequire-ab-specrunner'

When = require './whenFull'

fsp = require 'fs-promise' # uses fs-extra as well

tidyP = When.node.lift require('htmltidy').tidy

{ renderable, render, html, doctype, head, link, meta, script, p
body, title, h1, div, comment, ul, li, raw } = teacup = require 'teacup'

pkg = JSON.parse fsp.readFileSync __dirname + '/../../package.json'

spawn = require('child_process').spawn
execP = When.node.lift require("child_process").exec

gruntWatching = false

#@todo: modulerize as an extendible class, so other test frameworks can be based on it!

module.exports = specRunner = (err, specBB, options)->
  options = {} if !_B.isHash options # ignore the `afterBuild` async callback cause of the 3-args signature

  libBB = specBB.urequire.findBBExecutedBefore specBB

  if not libBB
    l.er err = "The library bundleBuilder is missing - you need to build the 'lib' you want to run the specs against, just before these specs."
    throw new Error '`urequire-ab-specrunner` error:' + err

  if require('compare-semver').lt libBB.urequire.VERSION, [minUrequireVersion]
    throw "`urequire` version >= '#{minUrequireVersion}' is needed for `urequire-ab-specrunner` version '#{pkg.version}'"

  {upath, grunt} = libBB.urequire # if running through `grunt-urequire` grunt is set, otherwise undefined

  _B.Logger.addDebugPathLevel 'urequire-ab-specrunner', options.debugLevel or 0

  _title = "libBundle `#{ libBB.build.target }`, specBundle: `#{ specBB.build.target }`"

  # setup any possible watch before returning cause of errors / nochanges
  if grunt and !gruntWatching and watchBB = _.find([libBB, specBB], (bb)-> bb.build.watch.enabled is true)
    gruntWatching = true
    task = "#{libBB.build.target}_#{specBB.build.target}"
    (watch = {})[task] =
      files: ["#{libBB.bundle.path}/**/*", "#{specBB.bundle.path}/**/*"]
      tasks: ["urequire:#{libBB.build.target}" , "urequire:#{specBB.build.target}"]
    watch.options = _.extend {spawn: false}, _.omit watchBB.build.watch, ['enabled', 'info']
    l.ok "Found `watch` at `#{watchBB.build.target}` - queueing `grunt-contrib-watch` task `watch:#{task}`.\n",
      if l.deb(30) then watch else ''
    grunt.config.merge 'watch': watch
    grunt.task.run "watch:#{task}"

    libBB.build.watch.enabled = true
    specBB.build.watch.enabled = true

  if not (libBB.build.hasChanged or specBB.build.hasChanged) and gruntWatching
    l.ok "No changes for `#{_title}` while `watch`-ing - not executing."
    return

  # check for errors in either lib or spec bbs
  for bb in [libBB, specBB]
    if bb.build.hasErrors
      if options.runOnErrors is true
        l.warn "Executing for `#{_title}` despite of errors in bundle `#{bb.build.target}` - cause `runOnErrors: true`"
      else
        l.er "Not executing for `#{_title}` cause of errors in bundle `#{bb.build.target}`"
        return

  l.ok "Executing for #{_title}."

  isAMD = not ((libBB.build.template.name is 'combined') and (specBB.build.template.name is 'combined'))

  # absolute dependency paths from lib, eg 'bower_components/lodash/lodash.compat', to blend into specs paths
  libRjsConf = libBB.build.calcRequireJsConfig '.'
  # paths relative to specsBB.build.dstPath, blendedWith lib's paths
  specRjsConf = specBB.build.calcRequireJsConfig null, libRjsConf
  l.deb 60, "All discovered paths, relative to specs dstPath:\n", specRjsConf.paths

  # make sure needed deps are available
  neededDepNames = _.uniq _.flatten([
    _.keys(libBB.bundle.local_nonNode_depsVars)
    _.keys(specBB.bundle.local_nonNode_depsVars)
    'mocha', 'chai' ]).map (dep)-> dep.split('/')[0] #cater for locals like 'when/callbacks'

  neededDepNames.push 'requirejs' if isAMD # usually not directly a dependency in lib/specs

  for dep in neededDepNames
    if (not specRjsConf.paths[dep]) and (dep isnt libBB.bundle.package.name)
      throw new Error """
        `urequire-ab-specrunner` error: `dependencies.paths.xxx` for `#{dep}` is undefined,
         so the HTML wont know where to load it from.
         You can either:
           a) `bower install #{dep}` and set `dependencies: paths: bower: true` in your config.
               uRequire will automatically find it (also delete `bower-paths-cache.json`).
           c) manually set `dependencies: paths: override` to the `#{dep}.js` lib eg
              `dependencies: paths: override: { '#{dep}': 'node_modules/#{dep}/path/to/#{dep}.js' }`
              (relative from project root)
         Then re-run uRequire.
        \n""" + l.prettify specRjsConf.paths

  # calc `require.config.paths` with blended the libBB paths
  if isAMD # paths relative to baseUrl (instead of specs dstPath), which will be set to lib's path
    rjsConf = specBB.build.calcRequireJsConfig libBB.build.dstPath, libRjsConf
  else  # paths are relative to specs `dstPath`,
    rjsConf = _.clone specRjsConf, true

  rjsConf.paths = _.pick rjsConf.paths, (v, depName)->
    (depName in neededDepNames) and depName not in ['mocha', 'requirejs'] #  filter only those needed

  l.deb 40, "Needed only `require.config.paths` for #{if isAMD then "AMD" else "plain <script>"}:\n", rjsConf.paths

  bb.bundle.ensureMain() if not bb.bundle.main for bb in [libBB, specBB]

  specToLibPath = upath.relative specBB.build.dstPath, libBB.build.dstPath
  libToSpecPath = upath.relative libBB.build.dstPath, specBB.build.dstPath

  # gather globals from options.global, dependencies.rootExports & rjs.shim exports
  getGlobalsPrint = ->
    allGLobals = _.unique _.filter (_B.arrayize(options.globals) or []).concat _.flatten (
      for bb in [libBB, specBB]
        _.map(bb.build?.rjs?.shim, 'exports')
          .concat(_.reduce bb.bundle.dependencies.rootExports, ((allRootExports, re)-> allRootExports.concat re), [] )
          .concat(_.reduce bb.bundle.local_nonNode_depsVars, ((localVars, lv)-> localVars.concat lv), [])
    )

    if !_.isEmpty allGLobals
      l.deb 50, "Discovered ", g = ".globals([#{ _.map(allGLobals, (exp)-> "'#{exp}'").join(', ') }])"
      g
    else ''

  generateHTML = ->
    HTML = teacup.render ->
      doctype 5
      html ->
        head ->
          meta charset: 'utf-8'
          title _title
        body ->
          h1 'urequire-ab-specrunner:' + _title
          div '#mocha'
        link rel: 'stylesheet', href: specRjsConf.paths.mocha[0] + '.css'
        # grunt-mocha / phantomjs require mocha & chai as plain <script> (using paths relative to specs dstPath)
        script src: specRjsConf.paths.mocha[0] + '.js'
        script src: specRjsConf.paths.chai[0] + '.js'

        script options.injectCode if options.injectCode
        raw options.injectRaw if options.injectRaw

        script """
          mocha.setup(#{
            if _.isString options.mochaSetup
              options.mochaSetup
            else
              if _B.isHash options.mochaSetup
                JSON.stringify options.mochaSetup, null, 2
              else
                "'bdd'"
          });"""

        if isAMD
          rjsConf.baseUrl = specToLibPath
          rjsConf.paths[libBB.bundle.package.name] = upath.trimExt libBB.build.dstMainFilename
          rjsConf.paths.libToSpecPath = libToSpecPath

          l.deb 30, "Final AMD `require.config`:\n", rjsConf

          script src: specRjsConf.paths.requirejs[0] + '.js'
          script "require.config(#{ JSON.stringify rjsConf, null, 2 });"
        else
          # loading all deps as <script>, sorted respecting shim order
          for dep in sortDeps _.keys(rjsConf.paths), rjsConf.shim
            script src: rjsConf.paths[dep] + '.js'

          comment "Loading library"
          script src: upath.join specToLibPath, libBB.build.dstMainFilename
          comment "Loading specs"
          script src: specBB.build.dstMainFilename

        comment "Run mocha in AMD or plain script, taking care of phantomjs"
        script (if isAMD
                  "require([ 'libToSpecPath/#{upath.trimExt specBB.build.dstMainFilename}' ], function() {"
                else
                  'if (!window.PHANTOMJS) {'
               ) + """\n
                      if (window.mochaPhantomJS) {
                        mochaPhantomJS.run()#{globs = getGlobalsPrint()};
                      } else {
                        mocha.run()#{globs};
                      }
                    }
               """ + (if isAMD then ");" else '')
    if options.tidy
      tidyP HTML
    else
      When HTML

  specPathHTML = "#{specBB.build.dstPath}/urequire-ab-specrunner-#{if isAMD then 'AMD' else 'script'}-#{libBB.build.target}_#{specBB.build.target}.html"
  writeHTMLSpec = (htmlText)->
    l.deb 80, "Saving spec HTML as `#{specPathHTML}`"
    fsp.outputFile specPathHTML, htmlText

  isHTMLsaved = false
  generateAndSaveHTML = ->
    if isHTMLsaved then When()
    else
      l.deb 50, "Generating spec HTML & saving as `#{specPathHTML}`"
      When.pipeline([generateHTML, writeHTMLSpec]).then ->
        l.deb 80, "Saved spec HTML to `#{specPathHTML}`"
        isHTMLsaved = true

  runMochaShell = (cmd, filename)->
    mochaParams  = _.filter((options.mochaOptions or '').split /\s/).concat filename
    l.deb 30, "Running shell `#{cmd} #{mochaParams.join ' '}`"
    if not options.exec #default
      cmd += '.cmd' if process.platform is "win32" # solves ENOENT http://stackoverflow.com/questions/17516772/using-nodejss-spawn-causes-unknown-option-and-error-spawn-enoent-err
      l.ok "spawn-ing `#{cmd} #{mochaParams.join ' '}`"
      When.promise (resolve, reject)->
        cp = spawn cmd, mochaParams
        cp.stdout.pipe process.stdout
        cp.stderr.pipe process.stderr
        cp.on 'close', (code)->
          if code is 0 then resolve() else
            reject new Error "`urequire-ab-specrunner` error: `#{cmd}` returned error code #{code}"
    else
      l.ok "exec-ing `#{cmd} #{mochaParams.join ' '}`"
      cmd = "#{cmd} #{mochaParams.join ' '}"
      execP(cmd).then(
        (res)-> l.log res[0]
        (err)-> l.err err
      )

  #  # UMD in nodejs mocha runner
  #  # write a "requirejs.config.json" with { baseUrl:"../UMD" } to spec's dstPath
  #  writeRequirejsConfig = ->
  #    fsp.writeFileP( upath.join(specBB.build.dstPath, "requirejs.config.json"),
  #      JSON.stringify({baseUrl:specToLibPath}, null, 2) , 'utf8')

  specRunners =
    'grunt-mocha':
      reject: ['nodejs']
      run: When.lift -> # @todo: must be the last one to run ?
        if grunt
          generateAndSaveHTML().then ->
            mocha = {}
            task = "#{libBB.build.target}_#{specBB.build.target}"
            mocha[task] = src: [specPathHTML]
            mocha[task].options = {run: true} if not isAMD # @todo: add grunt-mocha options ?
            grunt.config.merge 'mocha': mocha
            grunt.task.run "mocha:#{task}"
        else
          throw new Error "`urequire-ab-specrunner` error: Can't run specRunner `grunt-mocha` - not running through `grunt` & `grunt-urequire` >= v0.7.0"

    'mocha-phantomjs':
      reject: ['nodejs']
      run: ->
        generateAndSaveHTML().then ->
          runMochaShell 'mocha-phantomjs', specPathHTML

    'mocha-cli':
      reject: ['AMD']
      run: ->
        pkgJsonPath = "#{specBB.build.dstPath}/node_modules/#{libBB.bundle.package.name}/package.json"
        l.deb 50, "Saving a fake module of lib into spec's dstPath in `#{pkgJsonPath}`"
        fsp.outputFile(pkgJsonPath, JSON.stringify {
              "name": libBB.bundle.package.name
              "main": upath.join '../../', specToLibPath, libBB.build.dstMainFilename
            }, 'utf8'
        ).then ->
          runMochaShell 'mocha', specBB.build.dstMainFilepath

  templates = ['UMD', 'UMDplain', 'AMD', 'nodejs', 'combined']

  When.each _B.arrayize(options.specRunners or ['mocha-cli', 'mocha-phantomjs']), (name)->
    if not sr = specRunners[name]
      throw new Error "`urequire-ab-specrunner` error: unknown mocha specRunner '#{name}' - exiting."
    else
      for bb in [libBB, specBB]
        if bb.build.template.name in (sr.reject or [])
          if name in _B.arrayize options.specRunners or []
            throw new Error """
              `urequire-ab-specrunner` error: incompatible runtime - can't run requested specRunner `#{name}` with bundle `#{bb.build.target}` build with template `#{bb.build.template.name}`
                * You can use any template among #{l.prettify _.reject templates, (t)->t in sr.reject}
                * Use the default `specRunners` or any different one among #{
                    l.prettify _.keys _.pick specRunners, (spr)-> not bb.build.template.name in (spr.reject or [])
                  }
            """
          l.debug 80, "Ignoring incompatible runtime specRunner `#{name}` for  bundle `#{bb.build.target}` build with template `#{bb.build.template.name}`"
          return # silently ignore / dont run if not requested by user
      l.debug 80, "Invoking specRunner `#{name}` for lib `#{libBB.build.target}` against spec `#{specBB.build.target}`"
      sr.run()

specRunner.options = (opts)->
  (err, bb)-> specRunner err, bb, opts # promise-based fn signature must have 2 args

# yeah, we DO need bubblesort,
# deps are two-way and it's the simplest n^2 way
sortDeps = (arr, shim)->
  swap = (a, b)->
    temp = arr[a]
    arr[a] = arr[b]
    arr[b] = temp

  for dep_i, i in arr
    for dep_j, j in arr
      if arr[i] in (shim?[arr[j]]?.deps or [])
        swap j, i
  arr
