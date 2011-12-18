gem 'session'
require 'session'
require 'ostruct'

# This is a work in progress. I started getting annoyed with Simpleton when I was doing a mix of local and
# remote stuff with sudo ... and I don't want to rely on Capistrano or Vlad the Deployer since they tend to 
# be bloated. This is currently just one file, with a reliance on the Session gem.
module Cram

  class Deployment
    attr_reader :config

    def initialize(environment, &block)
      @environment = environment
      @config ||= OpenStruct.new
      @config.timestamp = Time.now.strftime("%Y%m%d%H%M%S")
      @tasks = []
      self.instance_eval(&block)
    end

    def task(description, &block)
      @tasks << Task.new(description, config, &block)
    end

    def run
      shell = Session.new
      puts "Running #{@environment}"
      @tasks.each { |task| task.run(shell) }
    end
  end # Deployment

  class Task
    attr_reader :config

    def initialize(description, config, &block)
      @description = description
      @config = config
      @commands = []
      self.instance_eval(&block)
    end

    def local(command, &block)
      @commands << [:local, "localhost", command]
      # @commands << [:local, "localhost", command, block]
    end

    def remote(command, &block)
      command = %Q{sudo -u #{@config.sudoer} -i -- -c "#{command}"} if @config.sudoer
      @config.hosts.each { |host| @commands << [:remote, host, command] }
      # @config.hosts.each { |host| @commands << [:remote, host, command, block] }
    end

    def scp(from, to)
      @config.hosts.each do |host|
        @commands << [:local, host, "scp #{from} #{host}:#{to}"]
      end
    end

    def run(shell)
      puts "# #{@description}"
      @commands.each do |command_struct|
        location, host, command = command_struct
        info(host, command)
        # do_it(location, host, command)
        command = "ssh #{host} '#{command}'" if location == :remote
        stdout, stderr = shell.execute(command, :stdin => StringIO.new)
        stdout.split("\n").each { |line| success(host, line) }
        stderr.split("\n").each { |line| error(host, line) }
        exit_if_failing(shell.exit_status)
      end
    end

    def info(host, line)    log "[\e[33m#{host}\e[0m]< #{line}"; end
    def success(host, line) log "[\e[32m#{host}\e[0m]> #{line}"; end
    def error(host, line)   log "[\e[31m#{host}\e[0m]E #{line}"; end
    def log(line) puts("  #{line}") unless line.empty?; end
  private
    def exit_if_failing(status)
      Process.exit(status) unless status.zero?
    end
  end # Task
end # Cram

class Object
  def deploy(*args, &block)
    Cram::Deployment.new(*args, &block).run
  end
end

