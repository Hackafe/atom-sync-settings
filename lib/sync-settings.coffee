# imports
{BufferedProcess} = require 'atom'
fs = require 'fs'
path = require 'path'
_ = require 'underscore-plus'

[GitHubApi, SyncManager, SyncImage, SyncDocument] = []


# constants
DESCRIPTION = 'Atom configuration storage operated by http://atom.io/packages/sync-settings'
REMOVE_KEYS = ["sync-settings"]

module.exports =
  config: require('./config.coffee')

  activate: ->
    GitHubApi ?= require 'github'
    SyncManager ?= require './sync-manager'
    SyncImage ?= require('./sync-image').instance.sync
    SyncDocument ?= require('./sync-document').instance.sync

    atom.commands.add 'atom-workspace', "sync-settings:backup", => @backup()
    atom.commands.add 'atom-workspace', "sync-settings:restore", => @restore()
    atom.commands.add 'atom-workspace', "sync-settings:view-backup", => @viewBackup()

  deactivate: ->

  serialize: ->

  backup: (cb=null) ->
    files = {}
    for own file, sync of SyncManager.get()
      files[file] = content: sync.reader()

    for file in atom.config.get('sync-settings.extraFiles') ? []
      file = path.join atom.getConfigDirPath(), file unless path.isAbsolute file
      switch path.extname(file).toLowerCase()
        when '.bmp', '.gif', '.jpg', '.jpeg', '.png', '.tiff'
          files[file] = content: SyncImage.reader file
        else
          files[file] = content: SyncDocument.reader file

    @createClient().gists.edit
      id: atom.config.get 'sync-settings.gistId'
      description: "automatic update by http://atom.io/packages/sync-settings"
      files: files
    , (err, res) ->
      console.log arguments
      if err
        console.error "error backing up data: "+err.message, err
        message = JSON.parse(err.message).message
        message = 'Gist ID Not Found' if message is 'Not Found'
        atom.notifications.addError "sync-settings: Error backing up your settings. ("+message+")"
      else
        atom.notifications.addSuccess "sync-settings: Your settings were successfully backed up. <br/><a href='"+res.html_url+"'>Click here to open your Gist.</a>"
      cb?(err, res)

  viewBackup: ->
    Shell = require 'shell'
    gistId = atom.config.get 'sync-settings.gistId'
    Shell.openExternal "https://gist.github.com/#{gistId}"

  restore: (cb=null) ->
    @createClient().gists.get
      id: atom.config.get 'sync-settings.gistId'
    , (err, res) =>
      if err
        console.error "error while retrieving the gist. does it exists?", err
        message = JSON.parse(err.message).message
        message = 'Gist ID Not Found' if message is 'Not Found'
        atom.notifications.addError "sync-settings: Error retrieving your settings. ("+message+")"
        return

      callbackAsync = false

      for own filename, file of res.files
        switch filename
          when 'settings.json'
            @applySettings '', JSON.parse(file.content) if atom.config.get('sync-settings.syncSettings')

          when 'packages.json'
            if atom.config.get('sync-settings.syncPackages')
              callbackAsync = true
              @installMissingPackages JSON.parse(file.content), cb

          when 'keymap.cson'
            fs.writeFileSync atom.keymaps.getUserKeymapPath(), file.content if atom.config.get('sync-settings.syncKeymap')

          when 'styles.less'
            fs.writeFileSync atom.styles.getUserStyleSheetPath(), file.content if atom.config.get('sync-settings.syncStyles')

          when 'init.coffee'
            fs.writeFileSync atom.config.configDirPath + "/init.coffee", file.content if atom.config.get('sync-settings.syncInit')

          when 'snippets.cson'
            fs.writeFileSync atom.config.configDirPath + "/snippets.cson", file.content if atom.config.get('sync-settings.syncSnippets')

          else fs.writeFileSync "#{atom.config.configDirPath}/#{filename}", file.content

      atom.notifications.addSuccess "sync-settings: Your settings were successfully synchronized."

      cb() unless callbackAsync

  createClient: ->
    token = atom.config.get 'sync-settings.personalAccessToken'
    console.debug "Creating GitHubApi client with token = #{token}"
    github = new GitHubApi
      version: '3.0.0'
      # debug: true
      protocol: 'https'
    github.authenticate
      type: 'oauth'
      token: token
    github
