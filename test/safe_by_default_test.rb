require_relative "test_helper"

class SafeByDefaultTest < Minitest::Test
  def setup
    StrongMigrations.safe_by_default = true
  end

  def teardown
    StrongMigrations.safe_by_default = false
  end

  def test_add_index
    assert_safe AddIndex
  end

  def test_add_index_extra_arguments
    assert_argument_error AddIndexExtraArguments
  end

  def test_add_index_corruption
    # TODO fix
    skip # unless postgresql?
    outside_developer_env do
      with_target_version(14.3) do
        assert_unsafe AddIndex, "can cause silent data corruption in Postgres 14.0 to 14.3"
      end
    end
  end

  def test_remove_index
    migrate AddIndex
    assert_safe RemoveIndex
    assert_safe RemoveIndexColumn
  ensure
    migrate AddIndex, direction: :down
  end

  def test_remove_index_name
    migrate AddIndexName
    migrate RemoveIndexName
  end

  def test_remove_index_options
    migrate RemoveIndexOptions
  end

  def test_remove_index_extra_arguments
    assert_argument_error RemoveIndexExtraArguments
  end

  def test_add_reference
    assert_safe AddReference
  end

  def test_add_reference_foreign_key
    assert_safe AddReferenceForeignKey
  end

  def test_add_reference_foreign_key_to_table
    assert_safe AddReferenceForeignKeyToTable
  end

  def test_add_reference_foreign_key_on_delete
    assert_safe AddReferenceForeignKeyOnDelete
  end

  def test_add_reference_extra_arguments
    assert_argument_error AddReferenceExtraArguments
  end

  def test_add_foreign_key
    assert_safe AddForeignKey
  end

  def test_add_foreign_key_after_failed_attempt
    skip unless postgresql?

    order = Order.create!
    invalid_order_id = order.id + 999
    user = User.create(order_id: invalid_order_id)

    error = assert_raises(ActiveRecord::StatementInvalid) do
      assert_safe AddForeignKeyName
    end

    assert_match "PG::ForeignKeyViolation: ERROR:  insert or update on table \"users\" violates foreign key constraint \"fk1\"\nDETAIL:  Key (order_id)=(#{invalid_order_id}) is not present in table \"orders\".\n", error.message

    user.update!(order_id: order.id)

    assert_safe AddForeignKeyName
  ensure
    User.delete_all
    Order.delete_all
  end

  def test_add_foreign_key_extra_arguments
    assert_argument_error AddForeignKeyExtraArguments
  end

  def test_add_foreign_key_name
    migrate AddForeignKeyName
    foreign_keys = ActiveRecord::Schema.foreign_keys(:users)
    assert_equal 2, foreign_keys.size
    if postgresql?
      assert foreign_keys.all? { |fk| fk.options[:validate] }
    end

    migrate AddForeignKeyName, direction: :down
    assert_equal 0, ActiveRecord::Schema.foreign_keys(:users).size
  end

  def test_add_foreign_key_column
    migrate AddForeignKeyColumn
    foreign_keys = ActiveRecord::Schema.foreign_keys(:users)
    assert_equal 2, foreign_keys.size
    if postgresql?
      assert foreign_keys.all? { |fk| fk.options[:validate] }
    end

    migrate AddForeignKeyColumn, direction: :down
    assert_equal 0, ActiveRecord::Schema.foreign_keys(:users).size
  end

  def test_add_check_constraint
    skip unless postgresql?

    assert_safe AddCheckConstraint
  end

  def test_add_check_constraint_after_failed_attempt
    skip unless postgresql?

    user = User.create!(credit_score: -1)

    error = assert_raises(ActiveRecord::StatementInvalid) do
      assert_safe AddCheckConstraint
    end
    assert_match  "PG::CheckViolation: ERROR:  check constraint \"users_credit_score_positive\" of relation \"users\" is violated by some row\n", error.message

    user.update!(credit_score: 1)

    assert_safe AddCheckConstraint
  ensure
    User.delete_all
  end

  def test_add_check_constraint_extra_arguments
    skip unless postgresql?

    assert_argument_error AddCheckConstraintExtraArguments
  end

  def test_change_column_null
    skip unless postgresql?

    User.create!(name: 'Jeff')

    assert_safe ChangeColumnNull
  ensure
    User.delete_all
  end

  def test_change_column_null_cleanup_constraint
    skip unless postgresql?

    # Create a user without a name
    user = User.create!(name: nil)
    temporary_constraint_name = 'users_name_null'

    error = assert_raises(ActiveRecord::StatementInvalid) do
      assert_safe ChangeColumnNull
    end

    assert_match  "PG::CheckViolation: ERROR:  check constraint \"#{temporary_constraint_name}\" of relation \"users\" is violated by some row\n", error.message

    user.update!(name: 'jeff')

    assert_safe ChangeColumnNull
  ensure
    User.delete_all
  end

  def test_change_column_null_default
    skip unless postgresql?

    # TODO add
    # User.create!
    error = assert_raises(StrongMigrations::Error) do
      assert_safe ChangeColumnNullDefault
    end
    assert_match "default value not supported yet with safe_by_default", error.message
  ensure
    User.delete_all
  end

  def test_add_index_with_invalid_present
    skip unless postgresql?

    User.create(name: 'same')
    duplicate = User.create(name: 'same')

    assert_raises(ActiveRecord::RecordNotUnique) do
      migrate SafeAddIndexColumnsUnique
    end

    duplicate.delete

    assert_safe SafeAddIndexColumnsUnique
  ensure
    User.delete_all
  end
end
