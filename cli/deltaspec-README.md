# deltaspec

Lightweight bash CLI for managing delta specs — change-driven specifications that describe modifications to architecture specs.

## Install

```bash
ln -sf ~/projects/local-projects/deltaspec/main/deltaspec ~/.local/bin/deltaspec
```

Or via `setup.sh` in ubuntu-note-system.

## Usage

```bash
deltaspec new change <name>       # Create a new change proposal
deltaspec status --change <name>  # Show artifact completion status
deltaspec list                    # List all changes
deltaspec archive <name>          # Archive completed change
deltaspec validate [name]         # Validate spec syntax
deltaspec instructions <artifact> # Get artifact build instructions
```

## Requirements

- bash 4.0+
- grep, sed, awk (standard coreutils)
- date, stat (for timestamps)
