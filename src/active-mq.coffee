# Description:
#   Interact with your Active MQ server
#
# Dependencies:
#   node-schedule
#
# Configuration:
#   HUBOT_ACTIVE_MQ_URL
#   HUBOT_ACTIVE_MQ_AUTH
#   HUBOT_ACTIVE_MQ_BROKER
#   HUBOT_ACTIVE_MQ_{1-N}_URL
#   HUBOT_ACTIVE_MQ_{1-N}_AUTH
#   HUBOT_ACTIVE_MQ_{1-N}_BROKER
#
#   Auth should be in the "user:password" format.
#
# Commands:
#   hubot mq list - lists all queues of all servers.
#   hubot mq stats <QueueName> - retrieves stats for given queue.
#   hubot mq s <QueueNumber> - retrieves stats for given queue. List queues to get number.
#   hubot mq stats - retrieves stats for broker of all servers.
#   hubot mq queue stats - retrieves stats for all queues
#   hubot mq servers - lists all servers and queues attached to them.
#   hubot mq alert list - list all alerts and their statuses
#   hubot mq alert start <AlertNumber> - starts given alert.  use alert list to get id
#   hubot mq alert start - starts all alerts
#   hubot mq alert stop <AlertNumber> - stops given alert.  use alert list to get id
#   hubot mq alert stop  - stops all alerts
#   hubot mq check <QueueName> every <X> <days|hours|minutes|seconds> and alert me when <queue size|consumer count> is (>|<|=|<=|>=|!=|<>) <Threshold> - Creates an alert that checks <QueueName> at time interval specified for conditions specified and alerts when conditions are met
#
# Author:
#   zack-hable
#
schedule = require('node-schedule')
STORE_KEY = 'hubot_active_mq'

Array::where = (query) ->
  return [] if typeof query isnt "object"
  hit = Object.keys(query).length
  @filter (item) ->
    match = 0
    for key, val of query
      match += 1 if item[key] is val
    if match is hit then true else false


class HubotMessenger
  constructor: (msg) ->
    @msg = msg

  msg: null

  _prefix: (message) =>
    "Active MQ says: #{message}"

  reply: (message, includePrefix = false) =>
    @msg.reply if includePrefix then @_prefix(message) else message

  send: (message, includePrefix = false) =>
    @msg.send if includePrefix then @_prefix(message) else message

  setMessage: (message) =>
    @msg = message

class ActiveMQServer
  url: null
  auth: null
  brokerName: null
  _hasListed: false
  _queues: null
  _querystring: null

  constructor: (url, brokerName, auth) ->
    @url = url
    @auth = auth
    @brokerName = brokerName
    @_queues = []
    @_querystring = require 'querystring'

  hasInitialized: ->
    @_hasListed

  addQueue: (queue) =>
    @_hasListed = true
    @_queues.push queue if not @hasQueueByName queue.destinationName

  getQueues: =>
    @_queues

  hasQueues: =>
    @_queues.length > 0

  hasQueueByName: (queueName) =>
    queueName = @_querystring.unescape(queueName).trim()
    @_queues.where(destinationName: queueName).length > 0

class ActiveMQAlert
  QUEUESIZE: "queue size"
  CONSUMERCOUNT: "consumer count"
  TOTAL_FAIL_THRESHOLD: 2
  
  constructor: (server, queue, reqFactory, type, time, timeUnit, comparisonOp, comparisonVal, robot, roomId) ->
    @server = server
    @queue = queue
    @robot = robot
    @_reqFactory = reqFactory
    @_time = time
    @_timeUnit = timeUnit
    @_type = type
    @_roomId = roomId
    @_compOp = comparisonOp
    @_compVal = comparisonVal
    @_job = null
    @_lastFailValue = null
    if (timeUnit.indexOf("days") != -1)
      @_pattern = "* * */#{time} * *"
    else if (timeUnit.indexOf("hours") != -1)
      @_pattern = "* */#{time} * * *"
    else if (timeUnit.indexOf("minutes") != -1)
      @_pattern = "*/#{time} * * * *"
    else if (timeUnit.indexOf("seconds") != -1)
      @_pattern = "*/#{time} * * * * *"
    else
      @_pattern = "* */10 * * * *"

  start: =>
    @_job = schedule.scheduleJob(@_pattern, @_handleAlert) if not @isRunning()

  stop: =>
    if @isRunning()
      @_job.cancel()
      @_job = null	

  isRunning: =>
    @_job != null
	
  nextRun: =>
    return @_job.nextInvocation() if @isRunning()

  toString: =>
    alertStatus = if @isRunning() then "ON" else "OFF"
    alertNextRun = if @isRunning() then "\nNext check: #{@nextRun()}"  else ""
    return "[#{alertStatus}] #{@queue} - Checks #{@_type} every #{@_time} #{@_timeUnit} and notifies when #{@_compOp} #{@_compVal} on #{@server.url}#{alertNextRun}"

  serialize: =>
    return [@server, @queue, @_type, @_time, @_timeUnit, @_compOp, @_compVal, @_roomId, @isRunning()]

  _alertFail: (value) =>
    if (value == null)
      return false

    if (@_compOp == ">")
      return value > @_compVal
    else if (@_compOp == "<")
      return value < @_compVal
    else if (@_compOp == "=")
      return value == @_compVal
    else if (@_compOp == "<=")
      return value <= @_compVal
    else if (@_compOp == ">=")
      return value >= @_compVal
    else if (@_compOp == "!=" or @_compOp == "<>")
      return value != @_compVal
    return false

  _alertFailFurther: (value) =>
    if (@_lastFailValue == null or value == null)
      return false

    if (@_compOp == ">")
      return value >= @_lastFailValue
    else if (@_compOp == "<")
      return value <= @_lastFailValue
    else if (@_compOp == "=")
      return value == @_lastFailValue
    else if (@_compOp == "<=")
      return value <= @_lastFailValue
    else if (@_compOp == ">=")
      return value >= @_lastFailValue
    else if (@_compOp == "!=" or @_compOp == "<>")
      return value != @_lastFailValue
    return false

  _handleAlert: =>
    @_reqFactory(@server, "api/jolokia/read/org.apache.activemq:type=Broker,brokerName=#{@server.brokerName},destinationType=Queue,destinationName=#{@queue}", @_handleAlertResponse)

  _handleAlertSecondCheck: =>
    if ((@_time > 30 and @_timeUnit.indexOf("seconds") != -1 or @_timeUnit.indexOf("seconds") == -1) and @_lastFailValue != null)
      console.log("Waiting 30 seconds before checking again")
      setTimeout ->
        @_handleAlert
      , 30000 

  _handleAlertResponse: (err, res, body, server) =>
    if err
      console.log(err)
      @robot.messageRoom(@_roomId, "An error occurred while contacting Active MQ")
      return

    try
      content = JSON.parse(body)
      content = content.value
      currentFail = null

      # load value we need to check against
      valueToCheck = null
      if (@_type == @QUEUESIZE)
        valueToCheck = content.QueueSize
      else if (@_type == @CONSUMERCOUNT)
        valueToCheck = content.ConsumerCount

      # check if it fails our checks
      if (@_alertFail(valueToCheck))
        currentFail = valueToCheck
        if (@_lastFailValue == null)
          @_lastFailValue = valueToCheck
          # wait 30 seconds and check the job again to see if its getting further from the alert threshold
          @_handleAlertSecondCheck
      else
        # no failures, reset last failure value
        @_lastFailValue = null

      if (@_alertFailFurther(currentFail))
        console.log("sending alert to client")
        @_lastFailValue = null
        @robot.messageRoom(@_roomId, ":rotating_light: #{@queue}'s #{@_type} is currently #{currentFail} and is getting further away from the alert value of #{@_compVal} :rotating_light:")
    catch error
      console.log(error)
      @robot.messageRoom(@_roomId, "An error occurred while contacting Active MQ")

  _handleQueueSizeAlert: (info) =>
    

class ActiveMQServerManager extends HubotMessenger
  _servers: []

  constructor: (msg) ->
    super msg
    @_loadConfiguration()

  getServerByQueueName: (queueName) =>
    @send "ERROR: Make sure to run a 'list' to update the queue cache" if not @serversHaveQueues()
    for server in @_servers
      return server if server.hasQueueByName(queueName)
    null

  hasInitialized: =>
    for server in @_servers
      return false if not server.hasInitialized()
    true

  listServers: =>
    @_servers

  serversHaveQueues: =>
    for server in @_servers
      return true if server.hasQueues()
    false

  servers: =>
    for server in @_servers
      queues = server.getQueues()
      message = "- #{server.url}"
      for queue in queues
        message += "\n-- #{queue.destinationName}"
      @send message

  _loadConfiguration: =>
    @_addServer process.env.HUBOT_ACTIVE_MQ_URL, process.env.HUBOT_ACTIVE_MQ_BROKER, process.env.HUBOT_ACTIVE_MQ_AUTH

    i = 1
    while true
      url = process.env["HUBOT_ACTIVE_MQ_#{i}_URL"]
      broker = process.env["HUBOT_ACTIVE_MQ_#{i}_BROKER"]
      auth = process.env["HUBOT_ACTIVE_MQ_#{i}_AUTH"]
      if url and broker and auth then @_addServer(url, broker, auth) else return
      i += 1

  _addServer: (url, broker, auth) =>
    @_servers.push new ActiveMQServer(url, broker, auth)


class HubotActiveMQPlugin extends HubotMessenger

  # Properties
  # ----------

  _serverManager: null
  _querystring: null
  # stores queues, across all servers, in flat list to support 'describeById'
  _queueList: []
  _params: null
  # stores a function to be called after the initial 'list' has completed
  _delayedFunction: null
  # stores how many queues have been described before sending the message
  _describedQueues = 0
  _queuesToDescribe = 0
  _describedQueuesResponse = null
  # stores the active alerts
  _alerts: []


  # Init
  # ----

  constructor: (msg, serverManager) ->
    super msg
    @_querystring   = require 'querystring'
    @_serverManager = serverManager
    @setMessage msg

  _init: (delayedFunction) =>
    return true if @_serverManager.hasInitialized()
    @reply "This is the first command run after startup. Please wait while we perform initialization..."
    @_delayedFunction = delayedFunction
    @list true
    false

  _initComplete: =>
    if @_delayedFunction != null
      @send "Initialization Complete. Running your request..."
      setTimeout((() =>
        @_delayedFunction()
        @_delayedFunction = null
      ), 1000)


  # Public API
  # ----------
  listAlert: =>
    return if not @_init(@listAlert)
    resp = ""
    index = 1
    for alertObj in @_alerts
      resp += "[#{index}] #{alertObj.toString()}\n"
      index++
    if (resp == "")
      resp = "It appears you don't have any alerts set up yet."
    @send resp

  stopAlert: =>
    return if not @_init(@stopAlert)
    alertObj = @_getAlertById()
    if !alertObj
      @msg.send "I couldn't find that alert. Try `mq alert list` to get a list."
      return
    alertObj.stop()
    alertId = parseInt(@msg.match[1])-1
    @robot.brain.get(STORE_KEY).alerts[alertId] = alertObj.serialize()
    @msg.send "This alert has been stopped"

  stopAllAlert: =>
    return if not @_init(@stopAllAlert)
    for alertObj, alertId in @_alerts
      alertObj.stop()
      @robot.brain.get(STORE_KEY).alerts[alertId] = alertObj.serialize()
    @msg.send "All alerts have been stopped"

  startAlert: =>
    return if not @_init(@startAlert)
    alertObj = @_getAlertById()
    if !alertObj
      @msg.send "I couldn't find that alert. Try `mq alert list` to get a list."
      return
    alertObj.start()
    alertId = parseInt(@msg.match[1])-1
    @robot.brain.get(STORE_KEY).alerts[alertId] = alertObj.serialize()
    @msg.send "This alert has been started"

  startAllAlert: =>
    return if not @_init(@startAllAlert)
    for alertObj, alertId in @_alerts
      alertObj.start()
      @robot.brain.get(STORE_KEY).alerts[alertId] = alertObj.serialize()
    @msg.send "All alerts have been started"

  deleteAlert: =>
    return if not @_init(@deleteAlert)
    alertObj = @_getAlertById()
    if !alertObj
      @msg.send "I couldn't find that alert. Try `mq alert list` to get a list."
      return
    alertObj.stop()
    alertId = parseInt(@msg.match[1])-1
    @_alerts.splice(alertId, 1)
    @robot.brain.get(STORE_KEY).alerts.splice(alertId, 1)
    @msg.send "This alert has been deleted"
 
  queueSizeAlertSetup: =>
    return if not @_init(@queueSizeAlertSetup)
    queue = @_getQueue(true)
    server = @_serverManager.getServerByQueueName(queue)
    if !server
      @msg.send "I couldn't find any servers with a queue called #{@_getQueue()}.  Try `mq servers` to get a list."
      return
    time = @msg.match[2]
    timeUnit = @msg.match[3]
    type = @msg.match[4]
    comparisonOp = @msg.match[5]
    comparisonVal = @msg.match[6]
    # todo: make this less slack dependent
    alertObj = new ActiveMQAlert(server, queue, @_requestFactorySingle, type, time, timeUnit, comparisonOp, comparisonVal, @robot, @msg.message.rawMessage.channel)
    @_alerts.push(alertObj)
    alertObj.start()
    @robot.brain.get(STORE_KEY).alerts.push(alertObj.serialize())
    @msg.send "I'll try my best to check #{queue} every #{time} #{timeUnit} and report here if I see #{type} #{comparisonOp} #{comparisonVal}."

  describeAll: =>
    return if not @_init(@describeAll)
    @_queuesToDescribe = 0
    @_describedQueues = 0
    @_describedQueuesResponse = ''
    for server in @_serverManager.listServers()
        @_queuesToDescribe += server.getQueues().length

    for server in @_serverManager.listServers()
      for queue in server.getQueues()
        @_requestFactorySingle server, "api/jolokia/read/org.apache.activemq:type=Broker,brokerName=#{server.brokerName},destinationType=Queue,destinationName=#{queue.destinationName}", @_handleDescribeAll

  describeById: =>
    return if not @_init(@describeById)
    queue = @_getQueueById()
    if not queue
      @reply "I couldn't find that queue. Try `mq list` to get a list."
      return  
    @_setQueue queue
    @describe()

  describe: =>
    return if not @_init(@describe)
    queue = @_getQueue(true)
    server = @_serverManager.getServerByQueueName(queue)
    if !server
      @msg.send "I couldn't find any servers with a queue called #{@_getQueue()}.  Try `mq servers` to get a list."
      return
    @_requestFactorySingle server, "api/jolokia/read/org.apache.activemq:type=Broker,brokerName=#{server.brokerName},destinationType=Queue,destinationName=#{queue}", @_handleDescribe

  list: (isInit = false) =>
    for server in @_serverManager.listServers()
      @_requestFactorySingle server, "api/jolokia/read/org.apache.activemq:type=Broker,brokerName=#{server.brokerName}", if isInit then @_handleListInit else @_handleList

  stats: =>
    for server in @_serverManager.listServers()
      @_requestFactorySingle server, "api/jolokia/read/org.apache.activemq:type=Broker,brokerName=#{server.brokerName}", @_handleStats

  servers: =>
    return if not @_init(@servers)
    @_serverManager.servers()

  setMessage: (message) =>
    super message
    @_params = @msg.match[3]
    @_serverManager.setMessage message

  setRobot: (robot) =>
    @robot = robot

  # Utility Methods
  # ---------------
  syncAlerts: =>
    if !@robot.brain.get(STORE_KEY)
      @robot.brain.set(STORE_KEY, {"alerts":[]})
    
    console.log("loading alerts from file...")
    if (@robot.brain.get(STORE_KEY).alerts)
      for alertObj in @robot.brain.get(STORE_KEY).alerts
        @_alertFromBrain alertObj...
    console.log("done loading alerts from file")

  _alertFromBrain: (server, queue, type, time, timeUnit, comparisonOp, comparisonVal, roomId, shouldBeRunning) =>
    try
      alertObj = new ActiveMQAlert(server, queue, @_requestFactorySingle, type, time, timeUnit, comparisonOp, comparisonVal, @robot, roomId)
      @_alerts.push(alertObj)
      if (shouldBeRunning)
        alertObj.start()
      console.log("Loaded #{alertObj.toString()}")
    catch error
      console.log("error loading alert from brain")

  _addQueuesToQueuesList: (queues, server, outputStatus = false) =>
    response = ""
    filter = new RegExp(@msg.match[2], 'i')
    for queue in queues
      # Add the  queue to the @_queueList
      attributes = queue.objectName.split("org.apache.activemq:")[1].split(",")
      for attribute in attributes
        attributeName = attribute.substring(0, attribute.indexOf("="))
        attributeValue = attribute.substring(attribute.indexOf("=")+1, attribute.length)
        queue[attributeName] = attributeValue
      server.addQueue(queue)
      index = @_queueList.indexOf(queue.destinationName)
      if index == -1
        @_queueList.push queue.destinationName
        index = @_queueList.indexOf(queue.destinationName)

      if filter.test queue.destinationName
        response += "[#{index + 1}] #{queue.destinationName} on #{server.url}\n"

    @send response if outputStatus

  _configureRequest: (request, server = null) =>
    defaultAuth = process.env.HUBOT_JENKINS_AUTH
    return if not server and not defaultAuth
    selectedAuth = if server then server.auth else defaultAuth
    request.header('Content-Length', 0)
    request

  _describeQueueAll: (queue) =>
    response = ""
    response += "#{queue.Name} :: Queue Size:#{queue.QueueSize}, Consumers:#{queue.ConsumerCount}\n"
    response

  _describeQueue: (queue) =>
    response = ""
    response += "Name: #{queue.Name}\n"
    response += "Paused: #{queue.Paused}\n"
    response += "Queue Size: #{queue.QueueSize}\n"
    response += "Consumer Count: #{queue.ConsumerCount}\n"
    response += "Memory Usage: #{queue.MemoryPercentUsage}%\n"
    response += "Cursor Usage: #{queue.CursorPercentUsage}%"
    response

  _describeStats: (stats) =>
    response = ""
    response += "Broker: #{stats.BrokerName}\n"
    response += "Uptime: #{stats.Uptime}\n"
    response += "Memory Usage: #{stats.MemoryPercentUsage}%\n"
    response += "Store Usage: #{stats.StorePercentUsage}%"
    response

  _getQueue: (escape = false) =>
    queue = @msg.match[1].trim()

    if escape then @_querystring.escape(queue) else queue

  # Switch the index with the queue name
  _getQueueById: =>
    @_queueList[parseInt(@msg.match[1]) - 1]

  _getAlertById: =>
    @_alerts[parseInt(@msg.match[1]) - 1]

  _requestFactorySingle: (server, endpoint, callback, method = "get") =>
    user = server.auth.split(":")
    if server.url.indexOf('https') == 0 then http = 'https://' else http = 'http://'
    url = server.url.replace /^https?:\/\//, ''
    path = "#{http}#{user[0]}:#{user[1]}@#{url}/#{endpoint}"
    request = @robot.http(path)
    @_configureRequest request, server
    request[method]() ((err, res, body) -> callback(err, res, body, server))

  _setQueue: (queue) =>
    @msg.match[1] = queue


  # Handlers
  # --------
  _handleDescribeAll: (err, res, body, server) =>
    if err
      @send err
      return

    try
      content = JSON.parse(body)
      @_describedQueuesResponse += @_describeQueueAll(content.value)
      @_describedQueues++
      @send @_describedQueuesResponse if @_describedQueues == @_queuesToDescribe
    catch error
      @send error
  
  
  _handleDescribe: (err, res, body, server) =>
    if err
      @send err
      return

    try
      content = JSON.parse(body)
      @send @_describeQueue(content.value)
    catch error
      @send error

  _handleStats: (err, res, body, server) =>
    if err
      @send err
      return

    try
      content = JSON.parse(body)
      @send @_describeStats(content.value)
    catch error
      @send error

  _handleList: (err, res, body, server) =>
    @_processListResult err, res, body, server

  _handleListInit: (err, res, body, server) =>
    @_processListResult err, res, body, server, false

  _processListResult: (err, res, body, server, print = true) =>
    if err
      @send err
      return

    try
      content = JSON.parse(body)
      @_addQueuesToQueuesList content.value.Queues, server, print
      @_initComplete() if @_serverManager.hasInitialized()
    catch error
      @send error


module.exports = (robot) ->
  console.log("robot startup!")

  # Factories
  # ---------

  _serverManager = null
  serverManagerFactory = (msg) ->
    _serverManager = new ActiveMQServerManager(msg) if not _serverManager
    _serverManager.setMessage msg
    _serverManager

  # Load alerts from file
  _plugin = new HubotActiveMQPlugin('', serverManagerFactory(''))
  _plugin.setRobot robot
  robot.brain.on 'loaded', ->
    console.log("Attempting to load alerts from file")
    _plugin.syncAlerts()

  pluginFactory = (msg) ->
    _plugin.setMessage msg
    _plugin.setRobot robot
    _plugin
  # Command Configuration
  # ---------------------

  
  robot.respond /m(?:q)? list( (.+))?/i, id: 'activemq.list', (msg) ->
    pluginFactory(msg).list()
	
  robot.respond /m(?:q)? queue stats/i, id: 'activemq.describeQueues', (msg) ->
    pluginFactory(msg).describeAll()

  robot.respond /m(?:q)? check (.*) every (\d+) (days|hours|minutes|seconds) and alert me when (queue size|consumer count) is (>|<|=|<=|>=|!=|<>) (\d+)/i, id: 'activemq.queueAlertSetup', (msg) ->
    pluginFactory(msg).queueSizeAlertSetup()

  robot.respond /m(?:q)? alert list/i, id: 'activemq.listAlert', (msg) ->
    pluginFactory(msg).listAlert()

  robot.respond /m(?:q)? alert stop (\d+)/i, id: 'activemq.stopAlert', (msg) ->
    pluginFactory(msg).stopAlert()

  robot.respond /m(?:q)? alert stop$/i, id: 'activemq.stopAllAlert', (msg) ->
    pluginFactory(msg).stopAllAlert()

  robot.respond /m(?:q)? alert start (\d+)/i, id: 'activemq.startAlert', (msg) ->
    pluginFactory(msg).startAlert()

  robot.respond /m(?:q)? alert start$/i, id: 'activemq.startAllAlert', (msg) ->
    pluginFactory(msg).startAllAlert()

  robot.respond /m(?:q)? alert delete (\d+)/i, id: 'activemq.deleteAlert', (msg) ->
    pluginFactory(msg).deleteAlert()

  robot.respond /m(?:q)? stats (.*)/i, id: 'activemq.describe', (msg) ->
    pluginFactory(msg).describe()
	
  robot.respond /m(?:q)? s (\d+)/i, id: 'activemq.d', (msg) ->
    pluginFactory(msg).describeById()

  robot.respond /m(?:q)? servers/i, id: 'activemq.servers', (msg) ->
    pluginFactory(msg).servers()

  robot.respond /m(?:q)? stats$/i, id: 'activemq.stats', (msg) ->
    pluginFactory(msg).stats()

  robot.activemq =
    queueAlertSetup: ((msg) -> pluginFactory(msg).queueAlertSetup())
    listAlert:       ((msg) -> pluginFactory(msg).listAlert())
    startAlert:      ((msg) -> pluginFactory(msg).startAlert())
    stopAlert:       ((msg) -> pluginFactory(msg).stopAlert())
    deleteAlert:     ((msg) -> pluginFactory(msg).deleteAlert())
    describe:        ((msg) -> pluginFactory(msg).describe())
    list:            ((msg) -> pluginFactory(msg).list())
    servers:         ((msg) -> pluginFactory(msg).servers())
    stats:           ((msg) -> pluginFactory(msg).stats())
