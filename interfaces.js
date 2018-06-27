module.exports = function(RED) {
  var exec = require('ttbd-exec');
  var mustache = require('mustache');
  var fs = require('fs');
  var path = require('path');

  var exec_opt = {
    hydra_exec_host: "mosquitto",
    type: "bash"
  }

  function isIP(val){
    if(val && /^(?!0)(?!.*\.$)((1?\d?\d|25[0-5]|2[0-4]\d)(\.|$)){4}$/.test(val)){
      return true
    }
    return false
  }

  function InterfacesNode(n) {
    RED.nodes.createNode(this,n);
    this.name = n.name;
    var node = this;

    this.on("input", function(msg) {
      var err = []
      if(msg.hasOwnProperty('iface') && msg.iface){
        if(msg.hasOwnProperty('iface_type') && msg.iface_type){
          let iface_type = msg.iface_type.toLowerCase()
          if(['dynamic', 'static'].indexOf(iface_type) != -1){
            if(iface_type === 'dynamic' || (iface_type === 'static' && msg.hasOwnProperty('static_ip') && isIP(msg.static_ip) && msg.hasOwnProperty('gateway')) && isIP(msg.gateway)){
              let scriptBase = fs.readFileSync(path.join(__dirname, 'scripts', ((iface_type==='dynamic')?'set_dhcp.sh':'set_static.sh')), {encoding: 'utf8'})
              let toInject = {
                net_env_interface: msg.iface
              }
              let script
              if(iface_type === 'static'){
                if(!msg.hasOwnProperty('subnet_mask') || !isIP(msg.subnet_mask)){
                  msg.subnet_mask = '255.255.255.0'
                }
                let masks = msg.subnet_mask.split('.')
                let mask = 0
                for(var index in masks){
                  mask += (masks[index] >>> 0).toString(2).replace(/0/g,'').length
                }

                toInject['net_env_static_ip'] = msg.static_ip
                toInject['net_env_subnet_mask'] = mask
                toInject['net_env_gateway'] = msg.gateway
              }
              script = mustache.render(scriptBase, toInject)
              exec({file: script}, exec_opt, function(err, stdout, stderr) {
                msg.payload = []
                if(err){
                  msg.payload.push(err)
                }
                if(stdout){
                  msg.payload.push(stdout)
                }
                if(stderr){
                  msg.payload.push(stderr)
                }
                node.send(msg)
              })
            } else {
              if(!msg.hasOwnProperty('static_ip')){
                err[err.length] = "missing msg.static_ip"
              } else if (!isIP(msg.static_ip)){
                err[err.length] = `wrong msg.static_ip : ${msg.static_ip}`
              }
              if(!msg.hasOwnProperty('gateway')){
                err[err.length] = "missing msg.gateway"
              } else if (!isIP(msg.gateway)){
                err[err.length] = `wrong msg.gateway : ${msg.gateway}`
              }
            }
          } else {
            err[err.length] = `unknown msg.iface_type : ${msg.iface_type}`
          }
        } else {
          err[err.length] = "missing msg.iface_type"
        }
      } else {
        err[err.length] = "missing msg.iface"
      }

      if(err.length != 0){
        msg.payload = err
        node.send(msg)
      }
    });
  }
  RED.nodes.registerType("interfaces", InterfacesNode);
}
