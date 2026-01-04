# Personal Source Code Workspace

This directory contains multiple independent software projects for development and experimentation.

## Quick Start

### AdminU - Project Administration Menu

Run the `adminu` command to access an interactive menu for managing all projects:

```bash
/home/paul/src/adminu
```

Or create a symlink for easier access:

```bash
sudo ln -s /home/paul/src/adminu /usr/local/bin/adminu
# Then run from anywhere:
adminu
```

### Features

AdminU provides a unified single-page menu interface with quick actions:

#### Quick Action Commands
- **#** - Show detailed project menu (e.g., `5` for project 5)
- **#v** - View project overview/documentation (e.g., `5v`)
- **#r** - Run project (auto-detects: Docker, Django, Node.js, Make, etc.) (e.g., `5r`)
- **#t** - Test project (runs appropriate test suite) (e.g., `5t`)
- **#c** - Launch Claude Code CLI (e.g., `5c`)
- **#g** - Launch Google Gemini AI (e.g., `5g`)
- **#f** - Open File Manager (e.g., `5f`)
- **#o** - Open Terminal in project directory (e.g., `5o`)
- **q** - Quit AdminU

All actions are accessible from a single page - no need to navigate multiple menus!

### Project Types Detected

AdminU automatically detects project types:

- **Node.js** - Projects with `package.json`
- **Python** - Projects with `requirements.txt`
- **Django** - Projects with `manage.py`
- **Docker** - Projects with `docker-compose.yml`
- **Rust** - Projects with `Cargo.toml`
- **Go** - Projects with `go.mod`
- **Make** - Projects with `Makefile`
- **Bash** - Projects with `.sh` scripts

## Projects

This workspace contains 29+ projects including:

- **pando** - Django + React todo application with Docker deployment
- **security-scanner** - Automated security scanning system
- **pssh** - Parallel SSH execution tool
- **bash** - Bash source code
- **bashdb** - Bash debugger
- **fsociety** - Security toolkit
- **claude-code** - Claude Code project files
- And many more...

Each project may have its own documentation (`CLAUDE.md` or `README.md`) with specific build, test, and run instructions.

## AI Assistant Integration

### Claude Code

Most projects can be managed using Claude Code. Launch it via:

```bash
cd /home/paul/src/project-name
claude
```

Or use the AdminU menu option #4.

### Gemini

Access Google's Gemini AI via the AdminU menu option #5.

## Directory Structure

```
/home/paul/src/
├── adminu              # Project administration menu (this tool)
├── README.md           # This file
├── bash/               # Individual projects...
├── bashdb/
├── pando/
├── security-scanner/
└── ...
```

## Contributing

This is a personal workspace. Each project has its own standards and guidelines.
