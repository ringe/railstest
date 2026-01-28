# Version Compatibility Management

This document explains how railstest manages Ruby and Rails version compatibility.

## Features Implemented

### 1. Compatibility Matrix (lib/railstest/supported_versions.rb)

A centralized configuration that defines:
- Supported Ruby versions (2.5 - 3.3)
- Supported Rails versions (5.2 - 8.1)
- Compatibility mappings (which Ruby works with which Rails)
- Notes about specific versions (e.g., Docker image issues, requirements)

### 2. Validation Warnings (lib/railstest/cli.rb)

When users specify incompatible versions, the tool:
- Shows a clear warning with ⚠️ emoji
- Lists recommended Rails versions for that Ruby version
- Displays relevant notes (e.g., "Rails 8.0 requires Ruby 3.1+")
- Pauses for 2 seconds to ensure user sees the warning
- Proceeds anyway (allows users to experiment)

**Example:**
```
⚠️  Warning: Ruby 3.3 and Rails 5.2 may be incompatible
   Recommended Rails versions for Ruby 3.3: 7.1, 7.2, 8.0, 8.1

   Proceeding anyway, but build may fail...
```

### 3. README Compatibility Matrix

User-friendly table showing:
- Ruby versions with status indicators (✅ Recommended, ⚠️ Limited)
- Compatible Rails versions for each Ruby
- Notes about Docker image availability
- Last updated date

### 4. CI Testing (.github/workflows/test-combinations.yml)

Automated testing that:
- Runs monthly on the 1st of each month
- Can be manually triggered
- Tests common Ruby/Rails combinations:
  - Ruby 3.3 + Rails 7.1, 8.0
  - Ruby 3.2 + Rails 7.2
  - Ruby 3.1 + Rails 7.0
  - Ruby 3.0 + Rails 6.1
  - Ruby 2.7 + Rails 6.0, 5.2
- Creates a test fixture gem for each combination
- Reports successes and failures
- Reminds maintainers to update compatibility matrix

## Maintenance Schedule

### Monthly (Automated)
- CI runs automatically on the 1st
- Review CI results for failures

### Quarterly (Manual - 5 minutes)
1. Check for new Ruby/Rails releases
2. Update `lib/railstest/supported_versions.rb`:
   ```ruby
   compatibility: {
     "3.4" => ["7.2", "8.0", "8.1", "8.2"],  # Add new Ruby
     "3.3" => ["7.1", "7.2", "8.0", "8.1", "8.2"],  # Add new Rails
   }
   ```
3. Update `README.md` compatibility matrix
4. Update "Last updated" date in README

### When Issues Reported
- User reports combination doesn't work → Add to `notes` section
- User reports old version broken → Remove from `supported` arrays

## Testing Locally

Test compatibility warning:
```bash
# Should show warning (incompatible)
railstest --gem-path . --ruby 3.3 --rails 5.2

# Should not warn (compatible)
railstest --gem-path . --ruby 3.3 --rails 7.1
```

## Version Detection Strategy

The tool auto-detects versions conservatively:

**Will auto-detect:**
- Ruby >= 2.7 (modern, well-supported Docker images)
- Rails >= 7.0 (modern, active support)
- Exact version constraints in gemspec (e.g., `~> 3.0`)

**Won't auto-detect (requires manual `--ruby`/`--rails`):**
- Ruby < 2.7 (potential compatibility issues, old Docker images)
- Rails < 7.0 (older versions with potential breaking changes)
- Broad constraints (e.g., `>= 2.1.0` - too wide for safe detection)

This prevents the tool from making bad assumptions about old gems while providing convenience for modern projects.

## Adding New Versions

When Ruby 3.4 or Rails 8.2 is released:

1. **Update supported_versions.rb:**
   ```ruby
   ruby: {
     supported: ["2.5", "2.6", "2.7", "3.0", "3.1", "3.2", "3.3", "3.4"]
   },
   rails: {
     supported: ["5.2", "6.0", "6.1", "7.0", "7.1", "7.2", "8.0", "8.1", "8.2"]
   },
   compatibility: {
     "3.4" => ["7.2", "8.0", "8.1", "8.2"],
     "3.3" => ["7.1", "7.2", "8.0", "8.1", "8.2"],
     # ... update other entries as needed
   }
   ```

2. **Update README.md:**
   - Add row to compatibility matrix
   - Update "Last updated" date

3. **Update CI workflow (optional):**
   - Add test case for new version combination

4. **Test:**
   ```bash
   railstest --ruby 3.4 --rails 8.2
   ```

## Removing Old Versions

When a version becomes unsupported (e.g., Ruby 2.5 EOL):

1. Remove from `supported` array
2. Add note if relevant: `"2.5" => "EOL - use Ruby 2.7+"`
3. Update README with deprecation notice
4. Keep in compatibility matrix with ❌ status for reference

## Philosophy

- **Conservative auto-detection**: Only detect versions we're confident about
- **Helpful warnings**: Guide users without blocking them
- **Low maintenance**: Quarterly updates, automated CI testing
- **User control**: Always allow manual version specification
