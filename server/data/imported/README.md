# Imported Phrases Directory

This directory stores phrase files after successful database import.

## Purpose
- Archive successfully imported phrase collections
- Provide rollback reference if needed
- Track import history for development

## Contents (All Ignored by Git)
- `*.json` files - Successfully imported phrase collections
- Files are automatically moved here after database import
- Organized by import date and theme

## Note
All files in this directory are generated during the phrase import process and are ignored by git. They serve as local development references only.