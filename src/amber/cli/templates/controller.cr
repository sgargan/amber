require "./field.cr"

module Amber::CLI
  class Controller < Teeplate::FileTree
    directory "#{__DIR__}/controller"

    @name : String
    @actions = Hash(String, String).new
    @language : String

    def initialize(@name, actions)
      @language = language
      parse_actions(actions)
      add_route
      add_views
    end

    def parse_actions(actions)
      actions.each do |action|
        next unless action.size > 0
        split_action = action.split(":")
        @actions[split_action.first] = split_action[1]? || "get"
      end
    end

    def language
      if File.exists?(AMBER_YML) &&
         (yaml = YAML.parse(File.read AMBER_YML)) &&
         (language = yaml["language"]?)
        language.to_s
      else
        return "slang"
      end
    end

    def add_route
      routes = File.read("./config/routes.cr")
      replacement = <<-ROUTE
      routes :web do
          #{@actions.map { |action, verb| %Q(#{verb} "/#{@name}/#{action}", #{@name.capitalize}Controller, :#{action}) }.join("\n    ")}
      ROUTE
      File.write("./config/routes.cr", routes.gsub("routes :web do", replacement))
    end

    def add_views
      @actions.each do |action, verb|
        `mkdir -p src/views/#{@name}`
        `touch src/views/#{@name}/#{action}.#{language}`
      end
    end
  end
end
