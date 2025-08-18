# Server Data Directory

This directory contains generated and temporary files that should not be committed to git:

## Generated Files (Ignored)
- `*.json` - Phrase generation output files
- `import-report-*.json` - Import operation reports
- `phrases-*.json` - Generated phrase collections

## Imported Directory (Ignored)
- `imported/` - Successfully imported phrase files
- These files are moved here after successful database import
- Used for reference and rollback purposes only

## Note
All files in this directory are automatically generated during development and should not be manually edited or committed to version control.