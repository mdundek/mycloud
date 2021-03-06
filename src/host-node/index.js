const path = require("path");

global.appRoot = path.resolve(__dirname);

let MqttController = require("./controllers/mqtt/index");
let TaskController = require("./controllers/tasks/index");
let DBController = require("./controllers/db/index");
let OSController = require("./controllers/os/index");

require('dotenv').config();

MqttController.init();
TaskController.init(MqttController);
OSController.init(MqttController);
DBController.init();

