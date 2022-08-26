require 'phonelib'

class BrazilianNumberValidator < ActiveModel::EachValidator
  def validate_each(record, attribute, value)
    return if value.blank?

    phone = Phonelib.parse(value)

    return if phone.country != 'BR' || phone.valid? || phone.type != :mobile || phone.local_number.scan(/\d/).join.length >= 11

    record.errors.add(attribute, (options[:message] || 'Número esta inválido ou é um celular e precisa ter o nono digito!'))
  end
end
