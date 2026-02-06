---

## Dockerized Obsidian

For a quick and consistent way to run Obsidian, you can use the provided Docker Compose setup. This uses the `linuxserver/obsidian` image.

### Setup

1.  **Ensure Docker and Docker Compose are installed.**
2.  **`docker-compose.yml`**: This file is already in the repository root. It defines the Obsidian service.
3.  **`config/` directory**: This directory (also in the repository root) is mapped to `/config` inside the container. It is primarily for Obsidian's global application settings (which are minimal) and specific files the `linuxserver/obsidian` image might use.
    *   *Note*: Most Obsidian settings (themes, plugins, hotkeys) are **vault-specific** and stored within the `.obsidian` folder of each vault.
4.  **`vaults/` directory**: This directory (also in the repository root) is mapped to `/vaults` inside the container. This is where you will place your Obsidian vaults.
    *   A `vaults/default-vault/` has been created with a baseline configuration, including dark mode, and enabled "Backlinks", "Obsidian Bases", and "Daily Notes" core plugins.
    *   To use this pre-configured vault, select it when Obsidian first launches.
    *   To use an existing vault, copy its entire folder (e.g., `my-existing-vault/`) into the `vaults/` directory. If you want it to use the baseline config, copy the contents of `vaults/default-vault/.obsidian/` into your existing vault's `.obsidian/` folder.
    *   If you are starting fresh with a new vault, you can create an empty folder inside `vaults/` (e.g., `vaults/my-new-vault/`). Obsidian will prompt you to create a new vault or open an existing one when you first access it. You can then copy the `.obsidian` folder from `vaults/default-vault/` into your new vault for the baseline configuration.

### Configuration

The `docker-compose.yml` includes environment variables that you **must** customize:

*   **`PUID` and `PGID`**: These should match your host user's User ID (UID) and Group ID (GID) to prevent file permission issues between your host and the container.
    *   You can find your `PUID` by running `id -u` in your terminal.
    *   You can find your `PGID` by running `id -g` in your terminal.
*   **`TZ`**: Set this to your local timezone (e.g., `America/New_York`).
*   **`UMASK_SET`**: (Optional) Sets the file creation mask. `022` is a common value.

**Example `docker-compose.yml` snippet after customization:**

```yaml
services:
  obsidian:
    environment:
      - PUID=1000 # Your actual UID
      - PGID=1000 # Your actual GID
      - TZ=America/New_York
```

### Usage

1.  **Navigate to the repository root** in your terminal where `docker-compose.yml` is located.
2.  **Start the Obsidian container**:
    ```bash
    docker compose up -d
    ```
    This command will download the `linuxserver/obsidian` image (if not already present) and start the container in detached mode (in the background).
3.  **Access Obsidian**:
    *   Open your web browser and navigate to `http://localhost:3000` (for HTTP) or `https://localhost:3001` (for HTTPS).
    *   The first time you access it, Obsidian may prompt you to open an existing vault or create a new one. Select the vault you placed in the `vaults/` directory (e.g., `/vaults/my-vault`).
4.  **Stop the container**:
    ```bash
    docker compose down
    ```
5.  **Remove container and volumes (optional)**:
    ```bash
    docker compose down -v
    ```

This setup ensures your Obsidian notes and configurations are persistent on your host machine, even if you recreate the container.