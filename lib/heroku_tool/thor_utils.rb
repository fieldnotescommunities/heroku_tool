module HerokuTool
  module ThorUtils
    protected

    def puts_and_system(cmd)
      puts cmd
      puts "-------------"
      system_with_clean_env cmd
      puts "-------------"
    end

    def puts_and_exec(cmd)
      puts cmd
      exec_with_clean_env(cmd)
    end

    def system_with_clean_env(cmd)
      if defined?(Bundler) && Bundler.respond_to?(:with_unbundled_env)
        Bundler.with_unbundled_env { system cmd }
      elsif defined?(Bundler)
        Bundler.with_clean_env { system cmd }
      else
        system cmd
      end
    end

    def exec_with_clean_env(cmd)
      if defined?(Bundler) && Bundler.respond_to?(:with_unbundled_env)
        Bundler.with_unbundled_env { `#{cmd}` }
      elsif defined?(Bundler)
        Bundler.with_clean_env { `#{cmd}` }
      else
        `#{cmd}`
      end
    end
  end
end
