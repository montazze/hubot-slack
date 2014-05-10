{Robot, Adapter, TextMessage, EnterMessage, LeaveMessage} = require '../../hubot/node_modules/hubot'

SlackClient = require 'slack-client'
Util = require 'util'

class SlackBot extends Adapter
  constructor: (robot) ->
    @robot = robot

  run: ->
    # Take our options from the environment, and set otherwise suitable defaults
    options = 
      token: process.env.HUBOT_SLACK_TOKEN
      autoReconnect: true
      autoMark: true

    @robot.logger.info Util.inspect(options)
    return @robot.logger.error "No services token provided to Hubot" unless options.token

    @options = options

    # Create our slack client object
    @client = new SlackClient options.token, options.autoReconnect, options.autoMark

    # Setup event handlers
    # TODO: Handle eventual events at (re-)connection time for unreads and provide a config for whether we want to process them
    @client.on 'error', @.error
    @client.on 'loggedIn', @.loggedIn
    @client.on 'open', @.open
    @client.on 'close', @.close
    @client.on 'message', @.message

    # Start logging in
    @client.login()

  error: (error) =>
    @robot.logger.error "Received error #{error.toString()}"

  loggedIn: (self, team) =>
    @robot.logger.info "Logged in as #{self.name} of #{team.name}, but not yet connected"

    # Provide our name to Hubot
    @robot.name = self.name

  open: =>
    @robot.logger.info 'Slack client now connected'

    # Tell Hubot we're connected so it can load scripts
    @emit "connected"

  close: =>
    @robot.logger.info 'Slack client closed'

  message: (msg) =>
    return if msg.hidden
    return if not msg.text and not msg.attachments

    channel = @client.getChannelGroupOrDMByID msg.channel
    user = @client.getUserByID msg.user
    # TODO: Handle msg.username for bot messages?

    # Ignore our own messages
    return if user.name == @robot.name

    # Test for enter/leave messages
    if msg.subtype is 'channel_join' or msg.subtype is 'group_join'
      @robot.logger.debug "#{user.name} has joined #{channel.name}"
      @receive new EnterMessage user

    else if msg.subtype is 'channel_leave' or msg.subtype is 'group_leave'
      @robot.logger.debug "#{user.name} has left #{channel.name}"
      @receive new LeaveMessage user

    else if msg.subtype is 'channel_topic' or msg.subtype is 'group_topic'
      @robot.logger.debug "#{user.name} set the topic in #{channel.name} to #{msg.topic}"
      @receive new TopicMessage user, msg.topic, msg.ts

    else
      # Build message text to respond to, including all attachments
      txt = msg.getBody()

      # Process the user into a full hubot user
      user = @robot.brain.userForId user.name
      user.room = channel.name

      @robot.logger.debug "Received message: '#{txt}' in channel: #{channel.name}, from: #{user.name}"

      @receive new TextMessage user, txt, msg.ts

  send: (envelope, messages...) ->
    channel = @client.getChannelGroupOrDMByName envelope.room

    for msg in messages
      @robot.logger.debug "Sending to #{envelope.room}: #{msg}"

      channel.send msg

  reply: (envelope, messages...) ->
    @robot.logger.debug "Sending reply"

    for msg in messages
      # TODO: Don't prefix username if replying in DM
      @send envelope, "#{envelope.user.name}: #{msg}"

  topic: (params, strings...) ->
    channel = @client.getChannelGroupOrDMByName envelope.room
    channel.setTopic strings.join "\n"

exports.use = (robot) ->
  new SlackBot robot
