'use strict';

Package.describe({
  summary: 'WebRTC signalling for Meteor',
  name: 'fds:webrtc',
  version: '1.0.2',
  git: 'https://github.com/foxdog-studios/meteor-webrtc.git'
});

Package.onUse(function (api) {
  api.versionsFrom('1.0');

  api.use([
    'arunoda:streams@0.1.17',
    'coffeescript',
    'mongo-livedata',
    'reactive-var',
    'underscore'
  ]);

  api.addFiles('lib/shim.coffee', 'client');
  api.addFiles('lib/streams.coffee');
  api.addFiles('lib/server/permissions.coffee', 'server');
  api.addFiles('lib/client/webrtc_signaller.coffee', 'client');
});

Package.onTest(function (api) {
  api.use(['fds:webrtc', 'tinytest']);
});

