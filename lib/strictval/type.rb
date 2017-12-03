require 'bigdecimal'

module StrictVal

  class ValidationError < StandardError; end

  TYPE_ID_FIELD = :__type_id

  class Type

    STANDARD_VALIDATORS = {
      positive: ->(n, v){ raise "#{n} must be > 0 (#{v})" unless v > 0 },
      negative: ->(n, v){ raise "#{n} must be < 0 (#{v})" unless v < 0 },
      nonpositive: ->(n, v){ raise "#{n} must be <= 0 (#{v})" unless v <= 0 },
      nonnegative: ->(n, v){ raise "#{n} must be >= 0 (#{v})" unless v >= 0 },
      nonempty: ->(n, v){ raise "#{n} must be non-empty (#{v})" if v.empty? },
    }

    def initialize(opts = {})
      opts = opts.dup
      @null = !!opts.delete(:null)
      @immutable = !!opts.delete(:immutable)
      @validators = []
      supported_validators.each do |id, validator|
        if apply = opts.delete(id)
          @validators << validator
        end
      end
      if custom_validator = opts.delete(:validate)
        @validators << ->(n, v){custom_validator.call v}
      end
      raise "Unrecognized options: #{opts.keys}" unless opts.empty?
    end

    def supported_validators
      STANDARD_VALIDATORS
    end

    def immutable?
      @immutable
    end

    def validate(name, value)
      if value.nil?
        raise ValidationError, "#{name} cannot be nil" unless @null
        return
      end
      begin
        @validators.each{|v| v.call name, value}
      rescue => e
        raise ValidationError, e
      end
    end

    def deserialize(value)
      value
    end

    def serialize(value)
      value
    end

    def deep_freeze(value)
      return if value.nil?
      if @immutable
        value
      else
        raise NotImplementedError
      end
    end

  end

  class DescendantType < Type
    def initialize(parent_type, opts = {})
      super(opts)
      @parent_type = parent_type
    end
    def validate(name, value)
      super
      return if value.nil?
      raise ValidationError, "#{name} must be of type #{@parent_type}, found #{value}" unless value.kind_of?(@parent_type)
    end
    def to_s
      @parent_type.name
    end
  end

  class StructureType < DescendantType
    def initialize(structure, opts = {})
      super(structure, opts.merge(immutable: true))
      @structure = structure
    end
    def deserialize(value)
      return nil if value.nil?
      @structure.deserialize value
    end
    def serialize(value)
      value.serialize
    end
  end

  class TupleType < Type
    def initialize(types, opts = {})
      super(opts)
      @types = types.dup.freeze
    end
    def validate(name, value)
      super
      return if value.nil?
      unless value.kind_of?(Array) && value.length == @types.length
        raise ValidationError, "#{name} must be a tuple of #{self}, found #{value}"
      end
      @types.each_with_index do |t, i|
        t.validate "#{name}[#{i}]", value[i]
      end
    end
    def deserialize(value)
      return nil if value.nil?
      @types.each_with_index.map do |t, i|
        t.deserialize value[i]
      end
    end
    def serialize(value)
      return nil if value.nil?
      @types.each_with_index.map do |t, i|
        t.serialize value[i]
      end
    end
    def deep_freeze(value)
      return if value.nil?
      @types.each_with_index do |t, i|
        t.deep_freeze value[i]
      end
      value.freeze
    end
    def to_s
      "(#{@types.join ','})"
    end
  end

  class EnumType < Type
    def initialize(type, values, opts = {})
      super(opts)
      @type = type
      @values = values.dup.freeze
      @values.each{|v| type.deep_freeze v}
    end
    def validate(name, value)
      super
      return if value.nil?
      raise ValidationError, "#{name} must be one of #{@values}, found #{value}" unless @values.include? value
    end
    def deep_freeze(value)
      @type.deep_freeze value
    end
  end

  class ArrayType < DescendantType
    def initialize(type, opts = {})
      super(Array, opts)
      @type = type
    end
    def validate(name, value)
      super
      return if value.nil?
      value.each_with_index.map{|v, i| @type.validate "#{name}[#{i}]", v}
    end
    def deserialize(value)
      return nil if value.nil?
      value.map{|v| @type.deserialize v}
    end
    def serialize(value)
      return nil if value.nil?
      value.map{|v| @type.serialize v}
    end
    def deep_freeze(value)
      return if value.nil?
      value.each{|v| @type.deep_freeze v}
      value.freeze
    end
  end

  class HashType < DescendantType
    def initialize(key_type, value_type, opts = {})
      super(Hash, opts)
      @key_type = key_type
      @value_type = value_type
    end
    def validate(name, value)
      super
      return if value.nil?
      value.each do |k, v|
        @key_type.validate "#{name} key", k
        @value_type.validate "#{name} value", v
      end
    end
    def deserialize(value)
      return nil if value.nil?
      Hash[value.map do |k, v|
        [
          @key_type.deserialize(k),
          @value_type.deserialize(v)
        ]
      end]
    end
    def serialize(value)
      return nil if value.nil?
      Hash[value.map do |k, v|
        [
          @key_type.serialize(k),
          @value_type.serialize(v)
        ]
      end]
    end
    def deep_freeze(value)
      return if value.nil?
      value.each do |k, v|
        @key_type.deep_freeze k
        @value_type.deep_freeze v
      end
      value.freeze
    end
  end

  class PolyStructureType < Type
    # types is id => Class
    def initialize(id_to_structure, opts = {})
      super(opts.merge(immutable: true))
      @id_to_structure = Hash[id_to_structure.map{|i,s| [i.to_s, s]}]
    end
    def validate(name, value)
      super
      return if value.nil?
      matches = []
      structures = @id_to_structure.values
      structures.each do |s|
        matches << s if value.kind_of? s
      end
      raise ValidationError, "#{name} must be one of #{structures}; found #{value.class}" if matches.empty?
      raise ValidationError, "#{name} is ambiguous; given type #{value.class} matches #{matches}" if matches.length > 1
    end
    def serialize(value)
      return nil if value.nil?
      @id_to_structure.each do |id, structure|
        if value.kind_of? structure
          return value.serialize type_id: id
        end
      end
      raise "#{value.class} matches none of #{@id_to_structure.keys}"
    end
    def deserialize(value)
      @id_to_structure[value[TYPE_ID_FIELD.to_s]].deserialize value
    end
  end

  class BigDecimalType < DescendantType
    def initialize(opts)
      super(BigDecimal, opts.merge(immutable: true))
    end
    def deserialize(value)
      return nil if value.nil?
      BigDecimal.new value
    end
    def serialize(value)
      return nil if value.nil?
      value.to_s
    end
  end

  class StringType < DescendantType
    def initialize(opts)
      super(String, opts)
    end
    def deep_freeze(value)
      value.freeze
    end
  end

  def self.array(type, opts = {})
    ArrayType.new coerce_type(type), opts
  end

  def self.hash(key_type, value_type, opts = {})
    HashType.new coerce_type(key_type), coerce_type(value_type), opts
  end

  def self.tuple(types, opts = {})
    TupleType.new types.map{|t| coerce_type t}, opts
  end

  def self.enum(type, values, opts = {})
    EnumType.new coerce_type(type), values, opts
  end

  def self.descendant(type, opts = {})
    DescendantType.new type, opts
  end

  def self.string(opts = {})
    StringType.new opts
  end

  def self.integer(opts = {})
    DescendantType.new Integer, opts.merge(immutable: true)
  end

  def self.float(opts = {})
    DescendantType.new Float, opts.merge(immutable: true)
  end

  def self.big_decimal(opts = {})
    BigDecimalType.new opts
  end

  def self.boolean(opts = {})
    enum DescendantType.new(Object, immutable: true), [true, false], opts
  end

  def self.structure(structure, opts = {})
    StructureType.new structure, opts
  end

  def self.poly_structure(structure_map, opts = {})
    PolyStructureType.new structure_map, opts
  end

  def self.coerce_type(type, opts = {})
    return type if type.kind_of? Type
    return StructureType[type, opts] if type < Structure
    if type.kind_of?(Class)
      CLASS_COERCE_TYPES.each do |klass, coerce_type|
        return coerce_type if klass >= type
      end
    end
    # Note: arbitrary classes are not coerced to DescendantType since it
    # will usually cause deep_freeze to throw
    #return DescendantType[type, opts] if type.kind_of?(Class)
    raise "Invalid StrictVal::Type definition: #{type}"
  end

  CLASS_COERCE_TYPES = {
    String => StrictVal.string,
    Integer => StrictVal.integer,
    Float => StrictVal.float,
    TrueClass => StrictVal.boolean,
    FalseClass => StrictVal.boolean,
    BigDecimal => StrictVal.big_decimal,
  }

end
