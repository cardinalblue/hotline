// ------------------------
// See https://github.com/layerhq/layer-parse-module
//

var fs = require('fs');
var layer = require('cloud/layer-parse-module/layer-module.js');

var layerProviderID = 'adfadd6e-1014-11e5-a5df-9fa92d003905';
var layerKeyID      = 'ab4eaa84-10ad-11e5-9172-9fa92d006e08';
var privateKey      = fs.readFileSync('cloud/layer-parse-module/keys/layer-key.js');
layer.initialize(layerProviderID, layerKeyID, privateKey);

Parse.Cloud.define("generateToken", function(request, response) {
    var userID = request.params.userID;
    var nonce = request.params.nonce;
    if (!userID) throw new Error('Missing userID parameter');
    if (!nonce) throw new Error('Missing nonce parameter');
        response.success(layer.layerIdentityToken(userID, nonce));
});

