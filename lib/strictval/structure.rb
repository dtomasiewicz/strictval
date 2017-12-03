module StrictVal

  # TODO rename this to Value?
  class Structure

    def initialize(values = {})
      unrecognized = values.keys - self.class.get_fields
      raise "Unrecognized fields: #{unrecognized}" unless unrecognized.empty?
      self.class.each_field do |name, type|
        value = values[name]
        type.validate name, value
        instance_variable_set :"@#{name}", type.deep_freeze(value)
      end
      freeze
      validate
    end

    def validate
      raise NotImplementedError
    end

    def with(new_values = {})
      values = {}
      self.class.each_field do |name, type|
        var = :"@#{name}"
        next unless instance_variable_defined? var
        values[name] = instance_variable_get var
      end
      self.class.new values.merge(new_values)
    end

    def to_h
      values = {}
      self.class.each_field do |name, type|
        var = :"@#{name}"
        next unless instance_variable_defined? var
        values[name] = instance_variable_get var
      end
      values
    end

    def to_s
      values = ''
      self.class.each_field do |name, type|
        var = :"@#{name}"
        next unless instance_variable_defined? var
        value = instance_variable_get var
        values << "#{name}=#{value},"
      end
      values.chomp! ','
      "#{self.class.name}[#{values}]"
    end

    def serialize(opts = {})
      result = {}
      self.class.each_field do |name, type|
        var = :"@#{name}"
        next unless instance_variable_defined? var
        value = instance_variable_get var
        result[name.to_s] = type.serialize value
      end
      if type_id = opts[:type_id]
        result[TYPE_ID_FIELD.to_s] = type_id
      end
      result
    end

    # TODO these are quite inefficient

    def eql?(other)
      return false if other.nil? || !other.kind_of?(self.class)
      to_h.eql? other.to_h
    end

    def ==(other)
      eql? other
    end

    def hash
      to_h.hash
    end

  end

  class StructureBuilder

    attr_reader :fields
    attr_reader :validators

    def initialize
      @fields = {}
      @validators = []
    end

    def array(name, type, opts = {})
      field name, StrictVal.array(type, opts)
    end

    def hash(name, key_type, value_type, opts = {})
      field name, StrictVal.hash(key_type, value_type, opts)
    end

    def tuple(name, types, opts = {})
      field name, StrictVal.tuple(types, opts)
    end

    def enum(name, values, opts = {})
      field name, StrictVal.enum(values, opts)
    end

    def string(name, opts = {})
      field name, StrictVal.string(opts)
    end

    def float(name, opts = {})
      field name, StrictVal.float(opts)
    end

    def big_decimal(name, opts = {})
      field name, StrictVal.big_decimal(opts)
    end

    def integer(name, opts = {})
      field name, StrictVal.integer(opts)
    end

    def boolean(name, opts = {})
      field name, StrictVal.boolean(opts)
    end

    def structure(name, structure, opts = {})
      field name, StrictVal.structure(structure, opts)
    end

    def poly_structure(name, structure_map, opts = {})
      field name, StrictVal.poly_structure(structure_map, opts)
    end

    def field(name, type, opts = {})
      @fields[name.to_sym] = StrictVal.coerce_type type, opts
    end

    def validate(&block)
      @validators << block
    end

    def build(&block)
      klass = Class.new Structure
      fields = @fields
      validators = @validators

      klass.define_singleton_method :each_field do |&block|
        fields.each &block
      end

      klass.define_singleton_method :get_fields do
        fields.keys
      end

      klass.define_singleton_method :deserialize do |structure|
        values = {}
        each_field do |name, type|
          key = structure.has_key?(name) ? name : name.to_s
          values[name] = type.deserialize structure[key]
        end
        new values
      end

      fields.keys.each do |field|
        klass.class_eval do
          define_method field do
            instance_variable_get :"@#{field}"
          end
          define_method :validate do
            begin
              validators.each{|v| instance_exec &v}
            rescue => e
              raise ValidationError, e
            end
          end
        end
      end

      klass
    end

  end

end