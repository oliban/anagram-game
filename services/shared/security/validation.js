const Joi = require('joi');
const { body, param, query, validationResult } = require('express-validator');

/**
 * Security-focused validation utilities for all services
 * Prevents injection attacks, data corruption, and malformed requests
 */

// Common validation patterns
const PATTERNS = {
  // Alphanumeric with basic punctuation for user content
  SAFE_TEXT: /^[a-zA-Z0-9\s\-_.,!?'"()åäöÅÄÖ]*$/,
  // Player names - alphanumeric, spaces, basic international chars
  PLAYER_NAME: /^[a-zA-Z0-9\s\-_åäöÅÄÖ]{1,50}$/,
  // UUIDs for IDs
  UUID: /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i,
  // Language codes
  LANGUAGE: /^(en|sv)$/,
  // Tokens (alphanumeric only)
  TOKEN: /^[a-zA-Z0-9]{8,64}$/
};

// Common Joi schemas
const SCHEMAS = {
  playerId: Joi.string().guid({ version: 'uuidv4' }).required(),
  playerName: Joi.string().pattern(PATTERNS.PLAYER_NAME).min(1).max(50).required(),
  phraseContent: Joi.string().pattern(PATTERNS.SAFE_TEXT).min(1).max(500).required(),
  phraseHint: Joi.string().pattern(PATTERNS.SAFE_TEXT).max(1000).allow('').optional(),
  language: Joi.string().pattern(PATTERNS.LANGUAGE).required(),
  difficultyLevel: Joi.number().integer().min(1).max(100).required(),
  score: Joi.number().integer().min(0).max(999999).required(),
  token: Joi.string().pattern(PATTERNS.TOKEN).required(),
  boolean: Joi.boolean().required(),
  id: Joi.number().integer().positive().required()
};

/**
 * Express-validator middleware factory
 */
const createValidators = {
  // Player validation
  playerName: () => body('name')
    .matches(PATTERNS.PLAYER_NAME)
    .withMessage('Player name contains invalid characters or is too long')
    .isLength({ min: 1, max: 50 })
    .withMessage('Player name must be 1-50 characters')
    .trim()
    .escape(),

  playerId: (field = 'playerId') => param(field)
    .matches(PATTERNS.UUID)
    .withMessage('Invalid player ID format'),

  // Phrase validation
  phraseContent: () => body('content')
    .matches(PATTERNS.SAFE_TEXT)
    .withMessage('Phrase content contains invalid characters')
    .isLength({ min: 1, max: 500 })
    .withMessage('Phrase content must be 1-500 characters')
    .trim()
    .escape(),

  phraseHint: () => body('hint')
    .optional()
    .matches(PATTERNS.SAFE_TEXT)
    .withMessage('Phrase hint contains invalid characters')
    .isLength({ max: 1000 })
    .withMessage('Phrase hint must be max 1000 characters')
    .trim()
    .escape(),

  language: () => body('language')
    .matches(PATTERNS.LANGUAGE)
    .withMessage('Language must be "en" or "sv"'),

  difficultyLevel: () => body('difficultyLevel')
    .isInt({ min: 1, max: 100 })
    .withMessage('Difficulty level must be 1-100')
    .toInt(),

  // Token validation
  token: (field = 'token') => param(field)
    .matches(PATTERNS.TOKEN)
    .withMessage('Invalid token format'),

  // Score validation
  score: () => body('score')
    .isInt({ min: 0, max: 999999 })
    .withMessage('Score must be 0-999999')
    .toInt(),

  // Query parameter validation
  queryLimit: () => query('limit')
    .optional()
    .isInt({ min: 1, max: 100 })
    .withMessage('Limit must be 1-100')
    .toInt(),

  queryOffset: () => query('offset')
    .optional()
    .isInt({ min: 0 })
    .withMessage('Offset must be >= 0')
    .toInt()
};

/**
 * Validation result handler middleware
 */
const handleValidationErrors = (req, res, next) => {
  const errors = validationResult(req);
  if (!errors.isEmpty()) {
    console.log('🚫 VALIDATION: Request failed validation:', {
      url: req.url,
      method: req.method,
      errors: errors.array(),
      body: req.body,
      params: req.params,
      query: req.query
    });
    
    return res.status(400).json({
      error: 'Validation failed',
      details: errors.array().map(err => ({
        field: err.path,
        message: err.msg,
        value: err.value
      }))
    });
  }
  next();
};

/**
 * Joi schema validation middleware factory
 */
const validateSchema = (schema, target = 'body') => {
  return (req, res, next) => {
    const data = target === 'body' ? req.body : 
                 target === 'params' ? req.params :
                 target === 'query' ? req.query : req[target];

    const { error, value } = schema.validate(data, {
      abortEarly: false,
      stripUnknown: true,
      convert: true
    });

    if (error) {
      console.log('🚫 JOI VALIDATION: Request failed schema validation:', {
        url: req.url,
        method: req.method,
        target,
        errors: error.details,
        data
      });

      return res.status(400).json({
        error: 'Schema validation failed',
        details: error.details.map(detail => ({
          field: detail.path.join('.'),
          message: detail.message,
          value: detail.context?.value
        }))
      });
    }

    // Replace the target with sanitized/converted values
    req[target] = value;
    next();
  };
};

/**
 * Common validation schemas for different endpoints
 */
const ENDPOINT_SCHEMAS = {
  createPlayer: Joi.object({
    name: SCHEMAS.playerName,
    language: SCHEMAS.language.optional()
  }),

  createPhrase: Joi.object({
    content: SCHEMAS.phraseContent,
    hint: SCHEMAS.phraseHint,
    language: SCHEMAS.language,
    difficultyLevel: SCHEMAS.difficultyLevel.optional(),
    isGlobal: SCHEMAS.boolean.optional(),
    createdByPlayerId: SCHEMAS.playerId.optional()
  }),

  completePhrase: Joi.object({
    phraseId: SCHEMAS.id,
    playerId: SCHEMAS.playerId,
    score: SCHEMAS.score,
    completionTimeMs: Joi.number().integer().min(0).max(3600000).required(), // Max 1 hour
    userInput: Joi.string().max(1000).optional()
  }),

  generateLink: Joi.object({
    playerId: SCHEMAS.playerId,
    maxUses: Joi.number().integer().min(1).max(100).optional(),
    expiresInHours: Joi.number().integer().min(1).max(168).optional() // Max 1 week
  })
};

/**
 * SQL Injection prevention - sanitize strings for database queries
 */
const sanitizeForDatabase = (input) => {
  if (typeof input !== 'string') return input;
  
  // Remove potential SQL injection patterns
  return input
    .replace(/['";\\]/g, '') // Remove quotes and escape chars
    .replace(/(-{2,}|\/\*|\*\/)/g, '') // Remove SQL comments
    .replace(/\b(union|select|insert|update|delete|drop|create|alter|exec|execute)\b/gi, '') // Remove SQL keywords
    .trim();
};

/**
 * XSS prevention - sanitize strings for output
 */
const sanitizeForOutput = (input) => {
  if (typeof input !== 'string') return input;
  
  return input
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#x27;')
    .replace(/\//g, '&#x2F;');
};

module.exports = {
  PATTERNS,
  SCHEMAS,
  createValidators,
  handleValidationErrors,
  validateSchema,
  ENDPOINT_SCHEMAS,
  sanitizeForDatabase,
  sanitizeForOutput
};