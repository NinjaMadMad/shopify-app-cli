# frozen_string_literal: true
require "test_helper"
require "project_types/extension/extension_test_helpers"

module Extension
  module Commands
    class PushTest < MiniTest::Test
      include TestHelpers::FakeUI
      include ExtensionTestHelpers::TempProjectSetup
      include ExtensionTestHelpers::Messages

      def setup
        super
        ShopifyCli::ProjectType.load_type(:extension)
        setup_temp_project

        @version = Models::Version.new(
          registration_id: 42,
          last_user_interaction_at: Time.now.utc
        )
      end

      def test_help_implemented
        assert_nothing_raised do
          refute_nil Commands::Push.help
        end
      end

      def test_runs_register_command_if_extension_not_yet_registered
        @project.expects(:registered?).returns(false).once

        Commands::Register.any_instance.expects(:call).once
        Commands::Build.any_instance.stubs(:call)
        ShopifyCli::JsSystem.any_instance.stubs(:call).returns(true)
        Tasks::UpdateDraft.any_instance.stubs(:call).returns(@version)

        run_push
      end

      def test_does_not_run_register_command_if_extension_already_registered
        assert @project.registered?

        Commands::Register.any_instance.expects(:call).never
        Commands::Build.any_instance.stubs(:call)
        ShopifyCli::JsSystem.any_instance.stubs(:call).returns(true)
        Tasks::UpdateDraft.any_instance.stubs(:call).returns(@version)

        run_push
      end

      def test_runs_build_command
        Commands::Build.any_instance.expects(:call).once
        ShopifyCli::JsSystem.any_instance.stubs(:call).returns(true)
        Tasks::UpdateDraft.any_instance.stubs(:call).returns(@version)

        run_push
      end

      def test_updates_the_extensions_draft_version
        Commands::Build.any_instance.stubs(:call)
        ShopifyCli::JsSystem.any_instance.stubs(:call).returns(true)
        Tasks::UpdateDraft.any_instance.expects(:call)
          .with(
            context: @context,
            api_key: @api_key,
            registration_id: @registration_id,
            config: @test_extension_type.config(@context),
            extension_context: @test_extension_type.extension_context(@context)
          )
          .returns(@version)
          .once

        run_push
      end

      def test_shows_confirmation_message_with_time_updated_on_successful_update
        @version.last_user_interaction_at = Time.parse("2020-05-07 19:01:56 UTC")
        @version.location = "https://www.fakeurl.com"
        Commands::Build.any_instance.stubs(:call)
        ShopifyCli::JsSystem.any_instance.stubs(:call).returns(true)
        Tasks::UpdateDraft.any_instance.stubs(:call).returns(@version)

        io = capture_io { run_push }

        assert_message_output(io: io, expected_content: [
          @context.message("push.waiting_text"),
          @context.message("push.success_confirmation", @title, "May 07, 2020 19:01:56 UTC"),
          @context.message("push.success_info", "https://www.fakeurl.com"),
        ])
      end

      def test_displays_time_the_draft_was_updated_at_in_utc
        response_time = "2020-05-07T19:01:56-04:00"
        expected_formatted_time_in_utc = "May 07, 2020 23:01:56 UTC"

        @version.last_user_interaction_at = Time.parse(response_time)
        Commands::Build.any_instance.stubs(:call)
        ShopifyCli::JsSystem.any_instance.stubs(:call).returns(true)
        Tasks::UpdateDraft.any_instance.stubs(:call).returns(@version)

        io = capture_io { run_push }

        assert_message_output(io: io, expected_content: [
          @context.message("push.success_confirmation", @title, expected_formatted_time_in_utc),
        ])
      end

      def test_shows_error_messages_and_validation_errors_if_any_occurred_on_push
        @version.last_user_interaction_at = Time.parse("2020-05-07 19:01:56 UTC")
        @version.validation_errors = [
          Models::ValidationError.new(field: %w(test_field), message: "Error message"),
          Models::ValidationError.new(field: %w(test_field1 test_field2), message: "Error message2"),
        ]

        Commands::Build.any_instance.stubs(:call)
        ShopifyCli::JsSystem.any_instance.stubs(:call).returns(true)
        Tasks::UpdateDraft.any_instance.stubs(:call).returns(@version)

        io = capture_io { run_push }

        assert_message_output(io: io, expected_content: [
          @context.message("push.pushed_with_errors", "May 07, 2020 19:01:56 UTC"),
          "{{x}} test_field: Error message",
          "{{x}} test_field2: Error message2",
          @context.message("push.push_with_errors_info"),
        ])
      end

      private

      def run_push
        push_command = Commands::Push.new
        push_command.ctx = @context
        push_command.call({}, :push)
      end
    end
  end
end
