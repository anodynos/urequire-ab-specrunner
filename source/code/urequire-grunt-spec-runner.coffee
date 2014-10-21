_ = (_B = require 'uberscore')._
l = new _B.Logger 'urequire-grunt-spec-runner', 1

When = require 'when'
When.node = require 'when/node'

tidy = When.node.lift require('htmltidy').tidy

{ renderable, render, html, doctype, head, link, meta, script, p
body, title, h1, div, comment, ul, li } = teacup = require 'teacup'

getGlobalsPrint = (uConfig)-> '.globals(["' + '_' + '"])'

module.exports = When.lift (libBB, specBB, grunt, options = {})->
  if not libBB
    l.er err = "libBB is missing"
    throw new Error err

  if not specBB
    l.er err = "specBB is missing"
    throw new Error err

  l.ok _title = "urequire-grunt-spec-runner: Lib `#{ libBB.bundle.name }`, Spec: `#{ specBB.bundle.name }`"

  upath = libBB.urequire.upath

  libBBPaths = libBB.build.calcRequireJsConfig('.').paths

  rjsPaths = (rjsC = specBB.build.calcRequireJsConfig(null, libBBPaths)).paths

  neededDepNames = _.uniq _.flatten [
    _.keys(libBB.bundle.local_nonNode_depsVars)
    _.keys(specBB.bundle.local_nonNode_depsVars)
    'mocha', 'chai'
  ]

  for dep in neededDepNames
    if (not rjsPaths[dep]) and (dep isnt libBB.bundle.main)
      throw new Error """
        `urequire-grunt-spec-runner` error: `*dependencies.paths.#{dep}*` is undefined.

         Make sure you install `#{dep}` via `bower` (or `npm` NOT IMPLEMENTED) or manually and either:

          a) set `dependencies: bower: true` in your config and uEequire will automatically find it.

          b) manually set the `paths` (relative from project root) to the `#{dep}.js` lib eg
            `dependencies: paths: { '#{dep}': 'some/path/to/#{dep}.js' }`
        \n
      """ + l.prettify rjsPaths

  rjsC.baseUrl = upath.relative specBB.build.dstPath, libBB.build.dstPath
  rjsPaths.specsPathFromLib = upath.relative libBB.build.dstPath, specBB.build.dstPath

  specBB.bundle.inferMain() if not specBB.bundle.main

  tidy(
    teacup.render ->
      doctype 5
      html ->

        head ->
          meta charset: 'utf-8'
          title _title

        body ->
          h1 _title
          div '#mocha'

        link rel: 'stylesheet', href: rjsPaths.mocha[0] + '.css'

        comment "grunt-mocha / phantomjs requires mocha as plain <script>"
        script src: rjsPaths.mocha[0] + '.js'
        script src: rjsPaths.chai[0] + '.js'

        if true
          script src: rjsPaths.requirejs[0] + '.js'

        script "require.config(#{ JSON.stringify rjsC, null, 2 });"

        script """
            #{options.setupCode or ''}

            mocha.setup('bdd');

            require(["specsPathFromLib/#{specBB.bundle.main}"], function(){
              if (window.mochaPhantomJS) {
                mochaPhantomJS.run();
              } else {
                mocha.run()#{ getGlobalsPrint '' };
              }
            });
          """
  ).then (html)->
    fs = require 'fsp'
    fs.writeFileP(specBB.build.dstPath + '/SpecRunner_Generated.html', html, 'utf8').then ->
      if grunt
        grunt.config 'mocha', generated: src: ["#{specBB.build.dstPath}/SpecRunner_Generated.html"]
        grunt.task.run "mocha:generated"
      else
        l.warn "grunt argument is missing - cant run grunt tasks. You can test the generated HTML in your browser."
