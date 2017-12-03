module StrictVal

  def self.define(&block)
    builder = StructureBuilder.new
    builder.instance_exec &block
    builder.build
  end

end

require 'strictval/type'
require 'strictval/structure'