class ChangeFeatureFlagsToDecimalInAccounts < ActiveRecord::Migration[7.0]
  def up
    change_column :accounts, :feature_flags, :decimal, precision: 100, scale: 0
  end

  def down
    change_column :accounts, :feature_flags, :bigint
  end
end
