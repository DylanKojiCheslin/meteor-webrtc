class @WebRTCSignaller
  constructor: (@channelName, @servers, @config, @dataChannelConfig,
                mediaConfig) ->
    WebRTCSignallingStream.on @channelName, @handleMessage
    @setMediaConfig(mediaConfig)
    @_started = false
    @startedDep = new Deps.Dependency()
    @_inCall = false
    @inCallDep = new Deps.Dependency()
    @_message = null
    @messageDep = new Deps.Dependency()
    @_dataChannelOpen = false
    @dataChannelDep = new Deps.Dependency()
    @_localStreamUrl = null
    @_localStreamUrlDep = new Deps.Dependency()
    @_remoteStream = null
    @_remoteStreamDep = new Deps.Dependency()

  started: ->
    @startedDep.depend()
    @_started

  inCall: ->
    @inCallDep.depend()
    @_inCall

  getMessage: ->
    @messageDep.depend()
    @_message

  dataChannelIsOpen: ->
    @dataChannelDep.depend()
    @_dataChannelOpen

  getLocalStream: ->
    @_localStreamUrlDep.depend()
    @_localStreamUrl

  getRemoteStream: ->
    @_remoteStreamDep.depend()
    @_remoteStream

  setMediaConfig: (@mediaConfig) ->

  sendMessage: (message) ->
    WebRTCSignallingStream.emit(@channelName, message)

  handleMessage: (message) =>
    if message.sdp?
      @handleSDP(JSON.parse(message.sdp))
    else if message.candidate?
      @handleIceCandidate(JSON.parse(message.candidate))
    else
      @logError('Unknown message', meesage)
    @_changeInCall(true)

  _changeInCall: (state) ->
    @_inCall = state
    @inCallDep.changed()

  handleSDP: (sdp) =>
    remoteDescription = new SessionDescription(sdp)
    if remoteDescription.type == 'offer'
      # Create a new RTCPeerConnection
      if @rtcPeerConnection?
        @stop()
      @createRtcPeerConnection()
    @rtcPeerConnection.setRemoteDescription(remoteDescription,
                                            @onRemoteDescriptionSet,
                                            @logError)

  handleIceCandidate: (candidate) =>
    iceCandidate = new IceCandidate(candidate)
    @rtcPeerConnection.addIceCandidate(iceCandidate)

  onIceCandidate: (event) =>
    return unless event.candidate
    @sendMessage(candidate: JSON.stringify(event.candidate))

  createOffer: =>
    @createLocalStream(@_createOffer)

  _createOffer: =>
    @rtcPeerConnection.createOffer(@localDescriptionCreated, @logError)
    @_changeInCall(true)

  onDataChannel: (event) =>
    @dataChannel = event.channel
    @dataChannel.onmessage = @handleDataChannelMessage
    @dataChannel.onopen = @handleDataChannelStateChange
    @dataChannel.onclose = @handleDataChannelStateChange

  handleDataChannelMessage: (event) =>
    @_message = event.data
    @messageDep.changed()

  onAddStream: (event) =>
    @_remoteStream = URL.createObjectURL(event.stream)
    @_remoteStreamDep.changed()

  createLocalStream: (callback) ->
    # There may be no media config, for no video/audio
    unless @mediaConfig?
      return callback()
    addStreamToRtcPeerConnection = =>
      @rtcPeerConnection.addStream(@_localStream)
    if @_localStream? and _.isEqual(@mediaConfig, @_lastMediaConfig)
      # Already have a local stream and the media config has not changed, so
      # we will keep on using the same stream.
      addStreamToRtcPeerConnection()
      return callback()
    @_lastMediaConfig = _.clone(@mediaConfig)
    navigator.getUserMedia @mediaConfig, (stream) =>
      @_localStream = stream
      @_localStreamUrl = URL.createObjectURL(stream)
      addStreamToRtcPeerConnection()
      @_localStreamUrlDep.changed()
      if callback?
        callback()
    , @logError


  localDescriptionCreated: (description) =>
    @rtcPeerConnection.setLocalDescription(description,
                                           @onLocalDescriptionSet,
                                           @logError)

  onLocalDescriptionSet: =>
    @sendMessage(sdp: JSON.stringify(@rtcPeerConnection.localDescription))

  onRemoteDescriptionSet: =>
    return unless @rtcPeerConnection.remoteDescription.type == 'offer'
    @createLocalStream(@_createAnswer)

  _createAnswer: =>
    @rtcPeerConnection.createAnswer(@localDescriptionCreated, @logError)


  createRtcPeerConnection: ->
    @rtcPeerConnection = new RTCPeerConnection(@servers, @config)
    @rtcPeerConnection.onicecandidate = @onIceCandidate
    @rtcPeerConnection.ondatachannel = @onDataChannel
    @rtcPeerConnection.onaddstream = @onAddStream
    @_started = true
    @startedDep.changed()

  start: ->
    @createRtcPeerConnection()
    try
      @dataChannel = @rtcPeerConnection.createDataChannel('dataChannel',
                                                          @dataChannelConfig)
    catch error
      @logError(error)
      return
    @dataChannel.onmessage = @handleDataChannelMessage
    @dataChannel.onopen = @handleDataChannelStateChange
    @dataChannel.onclose = @handleDataChannelStateChange

  stop: ->
    @dataChannel.close()
    @rtcPeerConnection.close()
    @rtcPeerConnection = null
    @_started = false
    @startedDep.changed()
    @_changeInCall(false)

  sendData: (data) ->
    @dataChannel.send(data)

  handleDataChannelStateChange: =>
    readyState = @dataChannel.readyState
    console.log "data channel state: #{readyState}"
    @_dataChannelOpen = readyState == 'open'
    @dataChannelDep.changed()

  logError: (message) ->
    console.error message

