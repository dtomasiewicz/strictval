#!/usr/bin/env ruby
# TODO proper tests

$:.unshift File.join(File.dirname(__FILE__), 'lib')
require 'strictval'
require 'json'

Hobby = StrictVal.define do
  string :desc
  integer :difficulty, validate: :positive
end

Person = StrictVal.define do
  string :name
  array :hobbies, StrictVal.structure(Hobby), null: true, validate: :nonempty
  validate{ raise "Name must begin with a J!" unless name[0] == 'J' }
end

joe = Person.new name: 'Joe', hobbies: [Hobby.new(desc: 'golfing', difficulty: 20)]
joe2 = Person.deserialize joe.serialize
raise "Deserialized Person should match" unless joe == joe2

begin
  Person.new name: 'Alice'
  raise "Person named Alice should be invalid"
rescue StrictVal::ValidationError
end

begin
  Person.new name: 'Joe', hobbies: []
  raise "Person with empty hobbies should be invalid"
rescue StrictVal::ValidationError
end
