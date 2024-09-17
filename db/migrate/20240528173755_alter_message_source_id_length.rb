class AlterMessageSourceIdLength < ActiveRecord::Migration[7.0]
  def change
    change_column :messages, :source_id, :string, limit: 512
  end
end
