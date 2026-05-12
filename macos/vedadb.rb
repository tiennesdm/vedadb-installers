# typed: false
# frozen_string_literal: true

# =============================================================================
# VedaDB Server - Homebrew Formula
# =============================================================================
# Description:
#   Homebrew formula for installing VedaDB Server on macOS.
#   Supports building from source (requires Go) or using release tarballs.
#   Installs binaries, generates default config, and sets up brew services.
#
# Usage:
#   brew tap vedadb/vedadb
#   brew install vedadb
#   # or
#   brew install vedadb --with-source
#
# Service Management:
#   brew services start vedadb
#   brew services stop vedadb
#   brew services restart vedadb
#
# For more information: https://vedadb.io/docs/installation/macos
# =============================================================================
class Vedadb < Formula
  desc "High-performance multi-model database server"
  homepage "https://vedadb.io"
  version "1.0.0"
  license "MIT"

  # Stable release (precompiled universal binary)
  stable do
    if Hardware::CPU.arm?
      url "https://github.com/vedadb/vedadb/releases/download/v#{version}/vedadb-#{version}-darwin-arm64.tar.gz"
      sha256 "0000000000000000000000000000000000000000000000000000000000000000"
    else
      url "https://github.com/vedadb/vedadb/releases/download/v#{version}/vedadb-#{version}-darwin-amd64.tar.gz"
      sha256 "0000000000000000000000000000000000000000000000000000000000000000"
    end
  end

  # Build from source (HEAD)
  head do
    url "https://github.com/vedadb/vedadb.git", branch: "main"

    depends_on "go" => :build
  end

  # Build dependencies (only when building from source)
  depends_on "go" => :build if build.head?

  # Runtime recommendations
  depends_on "curl" => :optional

  # =============================================================================
  # Download and Installation
  # =============================================================================
  def install
    if build.head?
      install_from_source
    else
      install_from_release
    end

    # Create data and log directories (owned by current user for Homebrew)
    (var/"vedadb/data").mkpath
    (var/"vedadb/logs").mkpath

    # Install default config if not present
    generate_default_config unless (etc/"vedadb/config.yaml").exist?
  end

  # =============================================================================
  # Install from pre-compiled release tarball
  # =============================================================================
  def install_from_release
    # Release tarballs contain: bin/, share/, etc/ directories
    bin.install "vedadb-server" if File.exist?("vedadb-server")
    bin.install "vedadb-cli" if File.exist?("vedadb-cli")
    bin.install "vedadb-bench" if File.exist?("vedadb-bench")
    bin.install "vedadb-backup" if File.exist?("vedadb-backup")
    bin.install "vedadb-config-generator" if File.exist?("vedadb-config-generator")

    # Install documentation
    share.install "LICENSE" if File.exist?("LICENSE")
    share.install "README.md" if File.exist?("README.md")
  end

  # =============================================================================
  # Build from source (HEAD or --build-from-source)
  # =============================================================================
  def install_from_source
    # Ensure Go module support
    ENV["CGO_ENABLED"] = "0"

    # Build all binaries with version info
    version_ldflags = %W[
      -s -w
      -X github.com/vedadb/vedadb/internal/version.Version=#{version}
      -X github.com/vedadb/vedadb/internal/version.BuildTime=#{Time.now.utc.iso8601}
      -X github.com/vedadb/vedadb/internal/version.GitCommit=HEAD
    ].join(" ")

    # Build server binary
    system "go", "build", "-o", bin/"vedadb-server",
           "-ldflags", version_ldflags,
           "./cmd/vedadb-server"

    # Build CLI binary
    system "go", "build", "-o", bin/"vedadb-cli",
           "-ldflags", version_ldflags,
           "./cmd/vedadb-cli"

    # Build benchmark tool (optional)
    if File.exist?("./cmd/vedadb-bench")
      system "go", "build", "-o", bin/"vedadb-bench",
             "-ldflags", version_ldflags,
             "./cmd/vedadb-bench"
    end

    # Build backup tool (optional)
    if File.exist?("./cmd/vedadb-backup")
      system "go", "build", "-o", bin/"vedadb-backup",
             "-ldflags", version_ldflags,
             "./cmd/vedadb-backup"
    end

    # Build config generator
    if File.exist?("./cmd/vedadb-config-generator")
      system "go", "build", "-o", bin/"vedadb-config-generator",
             "-ldflags", version_ldflags,
             "./cmd/vedadb-config-generator"
    end

    # Install documentation
    share.install "LICENSE" if File.exist?("LICENSE")
    share.install "README.md" if File.exist?("README.md")
  end

  # =============================================================================
  # Generate default configuration
  # =============================================================================
  def generate_default_config
    (etc/"vedadb").mkpath

    if (bin/"vedadb-config-generator").exist?
      # Use the config generator tool
      system bin/"vedadb-config-generator",
             "--os", "darwin",
             "--data-dir", "#{var}/vedadb/data",
             "--log-dir", "#{var}/vedadb/logs",
             "--output", "#{etc}/vedadb/config.yaml"
    else
      # Fallback: create minimal config directly
      (etc/"vedadb/config.yaml").write <<~YAML
        # ============================================================================
        # VedaDB Server Configuration
        # Auto-generated by Homebrew install
        # ============================================================================

        server:
          port: 7480
          host: 127.0.0.1
          data_dir: "#{var}/vedadb/data"
          max_connections: 1000
          query_timeout: 30s

        auth:
          enabled: true
          method: password
          admin_user: admin

        logging:
          level: info
          file: "#{var}/vedadb/logs/vedadb-server.log"
          max_size: 100MB
          max_files: 5
          format: json

        engines:
          document:
            enabled: true
          keyvalue:
            enabled: true
          graph:
            enabled: true
          vector:
            enabled: true
          timeseries:
            enabled: true
      YAML
    end
  end

  # =============================================================================
  # Post-Installation Hook
  # =============================================================================
  def post_install
    # Ensure data directories exist with correct permissions
    (var/"vedadb/data").mkpath
    (var/"vedadb/logs").mkpath

    # Ensure config exists
    generate_default_config unless (etc/"vedadb/config.yaml").exist?

    ohai "VedaDB Server post-install complete"
    ohai "Data directory: #{var}/vedadb/data"
    ohai "Config file:    #{etc}/vedadb/config.yaml"
    ohai "Logs:           #{var}/vedadb/logs"
  end

  # =============================================================================
  # Service Definition (for `brew services`)
  # =============================================================================
  service do
    run [opt_bin/"vedadb-server", "--config", etc/"vedadb/config.yaml"]
    keep_alive true
    restart_on_change true
    error_log_path var/"vedadb/logs/vedadb-server.error.log"
    log_path var/"vedadb/logs/vedadb-server.log"
    working_dir var/"vedadb"
    environment_variables PATH: std_service_path_env

    # Run as the user who installed (not root)
    run_type :immediate
  end

  # =============================================================================
  # Caveats - shown after installation
  # =============================================================================
  def caveats
    <<~EOS
      VedaDB Server #{version} has been installed!

      To start the service:
        brew services start vedadb

      To run manually (for development):
        vedadb-server --config #{etc}/vedadb/config.yaml

      To connect using the CLI:
        vedadb-cli --host localhost --port 7480

      Data directory: #{var}/vedadb/data
      Log files:      #{var}/vedadb/logs
      Config file:    #{etc}/vedadb/config.yaml

      First-time setup:
        The admin password was auto-generated during install. Check the logs:
          tail -f #{var}/vedadb/logs/vedadb-server.log

      For more information:
        https://docs.vedadb.io/getting-started
    EOS
  end

  # =============================================================================
  # Test
  # =============================================================================
  test do
    # Test that binaries exist and can show version
    assert_match(/vedadb-server version/i, shell_output("#{bin}/vedadb-server --version 2>&1"), 255)
    assert_match(/vedadb-cli/i, shell_output("#{bin}/vedadb-cli --version 2>&1"), 255)

    # Test config generation
    system bin/"vedadb-config-generator", "--os", "darwin", "--output", testpath/"test-config.yaml"
    assert_predicate testpath/"test-config.yaml", :exist?
  end
end
