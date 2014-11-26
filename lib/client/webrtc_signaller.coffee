class @WebRTCSignaller
  constructor: (@_channelName,
                @_servers,
                @_config,
                @_dataChannelConfig,
                mediaConfig) ->
    WebRTCSignallingStream.on @_channelName, @_handleMessage
    @setMediaConfig(mediaConfig)
    @_started = new ReactiveVar(false)
    @_inCall = new ReactiveVar(false)
    @_message = new ReactiveVar(null)
    @_dataChannelOpen = new ReactiveVar(false)
    @_localStreamUrl = new ReactiveVar(null)
    @_remoteStream = new ReactiveVar(null)

  started: ->
    @_started.get()

  inCall: ->
    @_inCall.get()

  getMessage: ->
    @_message.get()

  dataChannelIsOpen: ->
    @_dataChannelOpen.get()

  getLocalStream: ->
    @_localStreamUrl.get()

  getRemoteStream: ->
    @_remoteStream.get()

  setMediaConfig: (@mediaConfig) ->

  start: ->
    @_createRtcPeerConnection()
    if @_dataChannelConfig?
      @_tryCreateDataChannel()

  createOffer: ->
    @_createLocalStream(@_createOffer)

  requestCall: ->
    @_sendMessage(callMe: true)

  sendData: (data) ->
    throw 'No data channel created' unless @_dataChannel?
    @_dataChannel.send(data)

  stop: ->
    if @_dataChannel?
      @_dataChannel.close()
    if @_rtcPeerConnection?
      @_rtcPeerConnection.close()
    @_rtcPeerConnection = null
    @_started.set(false)
    @_changeInCall(false)

  _sendMessage: (message) ->
    WebRTCSignallingStream.emit(@_channelName, message)

  _handleMessage: (message) =>
    if message.callMe
      @stop()
      @start()
      @createOffer()
    else if message.sdp?
      @_handleSDP(JSON.parse(message.sdp))
    else if message.candidate?
      @_handleIceCandidate(JSON.parse(message.candidate))
    else
      @_logError('Unknown message', meesage)
    @_changeInCall(true)

  _changeInCall: (state) ->
    @_inCall.set state

  _handleSDP: (sdp) =>
    remoteDescription = new SessionDescription(sdp)
    if remoteDescription.type == 'offer'
      # Create a new RTCPeerConnection, resetting if necessary
      if @_rtcPeerConnection?
        @stop()
      @_createRtcPeerConnection()
    @_rtcPeerConnection.setRemoteDescription(remoteDescription,
                                            @_onRemoteDescriptionSet,
                                            @_logError)

  _handleIceCandidate: (candidate) =>
    iceCandidate = new IceCandidate(candidate)
    @_rtcPeerConnection.addIceCandidate(iceCandidate)

  _onIceCandidate: (event) =>
    return unless event.candidate
    @_sendMessage(candidate: JSON.stringify(event.candidate))

  _createOffer: =>
    @_rtcPeerConnection.createOffer(@_localDescriptionCreated, @_logError)
    @_changeInCall(true)

  _onDataChannel: (event) =>
    @_dataChannel = event.channel
    @_dataChannel.onmessage = @_handleDataChannelMessage
    @_dataChannel.onopen = @_handleDataChannelStateChange
    @_dataChannel.onclose = @_handleDataChannelStateChange

  _handleDataChannelMessage: (event) =>
    @_message.set event.data

  _onAddStream: (event) =>
    @_remoteStream.set URL.createObjectURL(event.stream)

  _createLocalStream: (callback) ->
    # There may be no media config, for no video/audio
    unless @mediaConfig?
      return callback()
    addStreamToRtcPeerConnection = =>
      @_rtcPeerConnection.addStream(@_localStream)
    if @_localStream? and _.isEqual(@mediaConfig, @_lastMediaConfig)
      # Already have a local stream and the media config has not changed, so
      # we will keep on using the same stream.
      addStreamToRtcPeerConnection()
      return callback()
    @_lastMediaConfig = _.clone(@mediaConfig)
    navigator.getUserMedia @mediaConfig, (stream) =>
      @_localStream = stream
      addStreamToRtcPeerConnection()
      @_localStreamUrl.set URL.createObjectURL(stream)
      if callback?
        callback()
    , @_logError

  _localDescriptionCreated: (description) =>
    @_rtcPeerConnection.setLocalDescription(description,
                                           @_onLocalDescriptionSet,
                                           @_logError)

  _onLocalDescriptionSet: =>
    @_sendMessage(sdp: JSON.stringify(@_rtcPeerConnection.localDescription))

  _onRemoteDescriptionSet: =>
    return unless @_rtcPeerConnection.remoteDescription.type == 'offer'
    @_createLocalStream(@_createAnswer)

  _createAnswer: =>
    @_rtcPeerConnection.createAnswer(@_localDescriptionCreated, @_logError)

  _createRtcPeerConnection: ->
    @_rtcPeerConnection = new RTCPeerConnection(@_servers, @_config)
    @_rtcPeerConnection.onicecandidate = @_onIceCandidate
    @_rtcPeerConnection.ondatachannel = @_onDataChannel
    @_rtcPeerConnection.onaddstream = @_onAddStream
    @_started.set(true)

  _tryCreateDataChannel: ->
    try
      @_dataChannel = @_rtcPeerConnection.createDataChannel('dataChannel',
                                                          @_dataChannelConfig)
    catch error
      @_logError("Unable to create data channel:#{error}")
      return
    @_dataChannel.onmessage = @_handleDataChannelMessage
    @_dataChannel.onopen = @_handleDataChannelStateChange
    @_dataChannel.onclose = @_handleDataChannelStateChange

  _handleDataChannelStateChange: =>
    readyState = @_dataChannel.readyState
    @_dataChannelOpen.set(readyState == 'open')

  _logError: (message) ->
    console.error message

