class AddDataToInboxMembers < ActiveRecord::Migration[7.2]
  def change
    add_column :inbox_members, :data, :json, if_not_exists: true
  end
end
