defmodule SimpleApp.Repo.Migrations.AddObanProTables do
  use Ecto.Migration

  def up, do: Oban.Pro.Migration.up()

  def down, do: Oban.Pro.Migration.down()
end
