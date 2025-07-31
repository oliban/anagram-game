// REMOVED: All contribution routes - Legacy system replaced by Link Generator Service (Legacy cleanup)
// Routes removed:
// - POST /api/contribution/request
// - GET /api/contribution/:token  
// - POST /api/contribution/:token/submit

const express = require('express');
const router = express.Router();

module.exports = (dependencies) => {
  return router;
};