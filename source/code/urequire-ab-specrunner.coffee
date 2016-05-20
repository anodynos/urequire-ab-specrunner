minUrequireVersion = "0.7.0-beta.27"
_B = require 'uberscore'
_ = require 'lodash'
l = new _B.Logger 'urequire-ab-specrunner'
_.mixin (require 'underscore.string').exports()

upath = require 'upath'
fsp = require 'fs-promise' # uses fs-extra as well
When = require './whenFull'
tidyP = When.node.lift require('htmltidy').tidy
spawn = require('child_process').spawn
execP = When.node.lift require("child_process").exec
{ renderable, render, html, doctype, head, link, meta, script, p
body, title, h1, h2, h3, h4, div, comment, ul, li, raw, table, tr, td, th, style } = teacup = require 'teacup'

pkg = JSON.parse fsp.readFileSync __dirname + '/../../package.json' # this is `urequire-ab-specrunner` 's package.json
isWatching = false

# @todo: modulerize as an extendible class, so other test frameworks can be based on it!
module.exports = specRunner = (err, specBB, options)->

  if @options             # using @options introduced in "0.7.0-beta.15"
    options = @options
  else
    if !_B.isHash options # support pre "0.7.0-beta.15"
      options = {}        # ignore the `afterBuild` async callback cause of the 3-args signature

  if not libBB = specBB.urequire.findBBExecutedBefore specBB
    err = """
      The library bundleBuilder is missing:
      You need to build the 'lib' you want to run the specs against, just before the specs.
      I.e execute something like `$ grunt lib spec`, where `spec` has `afterBuild: require('urequire-ab-specrunner')`
    """
    throw new Error '`urequire-ab-specrunner`:' + err

  if require('semver').lt libBB.urequire.VERSION, minUrequireVersion
    throw new Error "Incompatible `urequire` version '#{libBB.urequire.VERSION}'. You need `urequire` version >= '#{minUrequireVersion}' for `urequire-ab-specrunner` version '#{pkg.version}'"

  grunt = libBB.urequire.grunt # if running through `grunt-urequire` grunt is set, otherwise undefined
  _B.Logger.addDebugPathLevel 'urequire-ab-specrunner', options.debugLevel or 0
  _title = "lib.target:'#{ libBB.build.target }', spec.target:'#{ specBB.build.target }'"

  # invoke watch
  if grunt and (not isWatching) and
    (options.watch or _.any([libBB, specBB], (bb)-> bb.build.watch.enabled is true))
      isWatching = true
      watchesToBlend = [ # all blended as watch options
        before: "urequire:#{libBB.build.target}"
        options.watch
        specBB.build.watch
        libBB.build.watch
      ]
      watchesToBlend.debugLevel = options.debugLevel # not very neat
      require('urequire-ab-grunt-contrib-watch') err, specBB, watchesToBlend

  if not (libBB.build.hasChanged or specBB.build.hasChanged)
    if isWatching
      l.ok "No changes for `#{_title}` while `watch`-ing - not executing."
      return When()

  # check for errors in either lib or spec bbs
  for bb in [libBB, specBB]
    if bb.build.hasErrors
      if options.runOnErrors is true
        l.warn "Executing for `#{_title}` despite of errors in bundle `#{bb.build.target}` - cause `runOnErrors: true`"
      else
        l.er "Not executing for `#{_title}` cause of errors in bundle `#{bb.build.target}`"
        return When()

  l.ok "Executing for #{_title}."

  isAMD = not ((libBB.build.template.name is 'combined') and (specBB.build.template.name is 'combined'))
  isHTML = not ((libBB.build.template.name is 'nodejs') or (specBB.build.template.name is 'nodejs'))

  if isHTML
    # absolute dependency paths from lib, eg 'bower_components/lodash/lodash.compat', to blend into specs paths
    libRjsConf = libBB.build.calcRequireJsConfig '.', null, true
    # paths relative to specsBB.build.dstPath, blendedWith lib's paths
    rjsConf = fixPathsForNode specBB.build.calcRequireJsConfig null, libRjsConf, ['mocha', 'chai', 'requirejs'], [libBB.bundle.package.name]
    l.deb 60, "All rjsConf paths, relative to `specBB.build.dstPath = #{specBB.build.dstPath} `:\n", rjsConf.paths
    requirejs_path = rjsConf.paths.requirejs[0]
    mocha_path = rjsConf.paths.mocha[0]
    chai_path = rjsConf.paths.chai[0]

    if isAMD # paths relative to baseUrl (instead of specs dstPath), which will be set to lib's path
      rjsConf = fixPathsForNode specBB.build.calcRequireJsConfig libBB.build.dstPath, libRjsConf, true, [libBB.bundle.package.name]

    delete rjsConf.paths.mocha
    delete rjsConf.paths.requirejs
    l.deb 40, "Final needed only `require.config.paths` for #{if isAMD then "AMD" else "plain <script>"}:\n", rjsConf.paths

  specToLibPath = upath.relative specBB.build.dstPath, libBB.build.dstPath
  libToSpecPath = upath.relative libBB.build.dstPath, specBB.build.dstPath

  # gather globals from options.global, dependencies.rootExports & rjs.shim exports
  getGlobalsPrint = ->
    allGLobals = _.unique _.filter (_B.arrayize(options.globalsPrint) or []).concat _.flatten (
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

    addRow = (name, lib, spec)->
      tr ->
        td '.tg-70v4', name
        td '.tg-031e', lib or 'undefined'
        td '.tg-031e', spec or 'undefined'

    globalsPrint = getGlobalsPrint()

    HTML = teacup.render ->
      doctype 5
      html ->
        head ->
          meta charset: 'utf-8'
          title 'urequire-ab-specrunner:' + _title
        body ->
          h3 "Auto generated spec runner by `urequire-ab-specrunner` v'#{pkg.version}"
          style 'text/css', '.tg  {border-collapse:collapse;border-spacing:0;border-color:#aabcfe;}\n  .tg td{font-family:Arial, sans-serif;font-size:14px;padding:3px 20px;border-style:solid;border-width:1px;overflow:hidden;word-break:normal;border-color:#aabcfe;color:#669;background-color:#e8edff;}\n  .tg th{font-family:Arial, sans-serif;font-size:14px;font-weight:normal;padding:3px 20px;border-style:solid;border-width:1px;overflow:hidden;word-break:normal;border-color:#aabcfe;color:#039;background-color:#b9c9fe;}\n  .tg .tg-70v4{background-color:#cbcefb;color:#000000}'

          table '.tg', ->
            tr ->
              td '.tg-70v4', 'Loader'
              td '.tg-031e', if isAMD then "AMD (RequireJS `#{requirejs_path + '.js'}`)" else '<script/>'
            tr ->
              td '.tg-70v4', '.globals'
              td '.tg-031e', globalsPrint
            tr ->
              td '.tg-70v4', 'loaded deps'
              td '.tg-031e', _.keys(rjsConf.paths).join ', '
            tr ->
              td '.tg-70v4', 'watch'
              td '.tg-031e', if libBB.build.watch.enabled then "enabled (note: HTML not regenerated)" else 'disabled'

          table '.tg', ->
            tr ->
              th '.tg-031e'
              th '.tg-031e', 'lib'
              th '.tg-031e', 'spec'
            addRow 'build.dstPath', libBB.build.dstPath, specBB.build.dstPath
            addRow 'build.dstMainFilename', libBB.build.dstMainFilename,
              if (specBB.bundle.main or specBB.build.template.name is 'combined')
                specBB.build.dstMainFilename
              else
                'none (all spec files loaded)'
            addRow 'build.target', libBB.build.target, specBB.build.target
            addRow 'bundle.name', libBB.bundle.name, specBB.bundle.name
            addRow 'build.template', libBB.build.template.name, specBB.build.template.name

          div '#mocha'
        link rel: 'stylesheet', href: mocha_path + '.css'
        # grunt-mocha / phantomjs require mocha & chai as plain <script> (using paths relative to specs dstPath)
        script src: mocha_path + '.js'
        script src: chai_path + '.js'

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
          script src: requirejs_path + '.js'
          script "require.config(#{ JSON.stringify rjsConf, null, 2 });"
        else
          comment "Loading all deps as <script>, sorted with shim order"
          for dep in rjsConf.shimSortedDeps when dep isnt 'chai' # already loaded
            script src: rjsConf.paths[dep] + '.js'

          comment "Loading library"
          script src: upath.join specToLibPath, libBB.build.dstMainFilename
          comment "Loading specs"
          script src: specBB.build.dstMainFilename # of combined template

        comment "Invoke `mocha.run()` as #{if isAMD then 'AMD' else 'plain script'}, taking care of phantomjs"
        script (if isAMD
                  "require(['#{
                    (
                      if specBB.bundle.main or (specBB.build.template.name is 'combined')
                        [ specBB.build.dstMainFilename ]
                      else
                        (mod.dstFilename for k, mod of specBB.bundle.modules)
                    ).map((f)-> upath.join 'libToSpecPath/', upath.trimExt f).join("', '")
                  }'], function() {"
                else
                  'if (!window.PHANTOMJS) {'
               ) + """\n
                      if (window.mochaPhantomJS) {
                        mochaPhantomJS.run()#{globalsPrint};
                      } else {
                        mocha.run()#{globalsPrint};
                      }
                    }
               """ + (if isAMD then ");" else '')
    if options.tidy then tidyP(HTML) else When(HTML)

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
    mochaParams  = _.filter ((options.mochaOptions or '') + ' ' + filename).split /\s/
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

  specRunners =
    'grunt-mocha':
      reject: ['nodejs']
      run: When.lift ->
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
        fsp.outputFile(pkgJsonPath, JSON.stringify({
              "name": libBB.bundle.package.name
              "description": "A fake module for `#{libBB.bundle.package.name}` generated by `urequire-ab-specrunner` used by its specs."
              "main": upath.join(
                  libBB.bundle.package.name.split('/').map(-> '../').join('')   # back from `package.name` potentialy many paths (eg 'mycompany/mypackage')
                  '../'                                                         # back from node_modules
                  specToLibPath
                  libBB.build.dstMainFilename
              )
            }, null, 2), 'utf8'
        ).then ->
          runMochaShell './node_modules/.bin/mocha',
            if specBB.bundle.main or (specBB.build.template.name is 'combined')
              specBB.build.dstMainFilepath
            else
              "#{specBB.build.dstPath} --recursive"

  templates = ['UMD', 'UMDplain', 'AMD', 'nodejs', 'combined']

  specRunnersExecuted = 0
  When.each(_B.arrayize(options.specRunners or ['mocha-cli', 'mocha-phantomjs']), (name)->
    if not sr = specRunners[name]
      throw new Error "`urequire-ab-specrunner` error: unknown mocha specRunner '#{name}' - exiting."
    else
      for bb in [libBB, specBB]
        if bb.build.template.name in (sr.reject or [])
          if name in _B.arrayize options.specRunners
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
      specRunnersExecuted++
      sr.run()
  ).then ->
    if specRunnersExecuted is 0
      l.warn "No compatible specRunners were found to execute - check your templates compatibility (eg 'nodejs' + 'AMD' work go together)."
    else
      l.ok "Finished executing #{specRunnersExecuted} compatible specRunners."

# allow mocha, chai & requirejs to work from both node_modules & bower_components
fixPathsForNode = (rjsCfg)->
  if rjsCfg.paths.mocha
    rjsCfg.paths.mocha = _.uniq _.map rjsCfg.paths.mocha, (p)-> upath.dirname(p) + '/mocha'
  if rjsCfg.paths.chai
    rjsCfg.paths.chai = _.uniq _.map rjsCfg.paths.chai, (p)-> upath.dirname(p) + '/chai'
  if rjsCfg.paths.requirejs
    rjsCfg.paths.requirejs = _.uniq _.map rjsCfg.paths.requirejs, (p)-> p.replace('bin/r', 'require')
  rjsCfg

# passing options
specRunner.options = (opts)->
  (err, bb)-> specRunner err, bb, opts # promise-based fn signature must have 2 args
