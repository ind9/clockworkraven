class AddDataSplitToEvaluation < ActiveRecord::Migration
  def change
    add_column :evaluations, :data_split, :integer

  end
end
