const express = require('express');
const router = express.Router();

// Admin routes - administrative operations and batch operations

module.exports = (dependencies) => {
  const { 
    getDatabaseStatus, 
    DatabasePhrase, 
    broadcastActivity, 
    io
  } = dependencies;

  // Admin batch import endpoint removed for security
  // Use direct database script instead: node scripts/phrase-importer.js --input file.json --import

  return router;
};