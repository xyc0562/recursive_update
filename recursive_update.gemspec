$:.push File.expand_path("../lib", __FILE__)

# Maintain your gem's version:
require "recursive_update/version"

# Describe your gem and declare its dependencies:
Gem::Specification.new do |s|
  s.name        = "recursive_update"
  s.version     = RecursiveUpdate::VERSION
  s.authors     = ["Yecheng Xu"]
  s.email       = ["xyc0562@gmail.com"]
  s.homepage    = "TODO"
  s.summary     = "TODO: Summary of RecursiveUpdate."
  s.description = "TODO: Description of RecursiveUpdate."
  s.license     = "MIT"

  s.files = Dir["{app,config,db,lib}/**/*", "MIT-LICENSE", "Rakefile", "README.rdoc"]
  s.test_files = Dir["test/**/*"]

  s.add_dependency "rails", "~> 4.2.4"

  s.add_development_dependency "sqlite3"
end
