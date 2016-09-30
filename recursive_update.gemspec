$:.push File.expand_path("../lib", __FILE__)

# Maintain your gem's version:
require "recursive_update/version"

# Describe your gem and declare its dependencies:
Gem::Specification.new do |s|
  s.name        = "recursive_update"
  s.version     = RecursiveUpdate::VERSION
  s.authors     = ["Yecheng Xu"]
  s.email       = ["xyc0562@gmail.com"]
  s.homepage    = "https://github.com/xyc0562/recursive_update"
  s.summary     = "Customized nested & batch resource update and creation"
  s.description = "This Gem allows users to conveniently create/update arbitrarily nested resources in a batch. It also comes" +
      "with properly nested error messages"
  s.license     = "MIT"

  s.files = Dir["{app,config,db,lib}/**/*", "MIT-LICENSE", "Rakefile", "README.rdoc"]
  s.test_files = Dir["test/**/*"]

  s.add_dependency "rails"

  s.add_development_dependency "sqlite3"
end
