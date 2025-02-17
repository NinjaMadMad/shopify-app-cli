# frozen_string_literal: true

require "project_types/script/test_helper"

describe Script::Layers::Infrastructure::AssemblyScriptTaskRunner do
  include TestHelpers::FakeFS
  let(:ctx) { TestHelpers::FakeContext.new }
  let(:script_id) { "id" }
  let(:script_name) { "foo" }
  let(:extension_point_config) do
    {
      "rust" => {
        "package": "https://github.com/Shopify/scripts-apis-rs",
        "beta": true,
      },
    }
  end
  let(:extension_point_type) { "payment_filter" }
  let(:language) { "rust" }
  let(:rs_task_runner) { Script::Layers::Infrastructure::RustTaskRunner.new(ctx, script_name) }
  let(:script_project) do
    TestHelpers::FakeScriptProject
      .new(language: language, extension_point_type: extension_point_type, script_name: script_name)
  end

  before do
    Script::ScriptProject.stubs(:current).returns(script_project)
  end

  def system_output(msg:, success:)
    [msg, OpenStruct.new(success?: success)]
  end

  describe ".build" do
    subject { rs_task_runner.build }
    it "should raise if the build command fails" do
      ctx
        .expects(:capture2e)
        .with("cargo build --target=wasm32-unknown-unknown --release")
        .returns(system_output(msg: "", success: false))

      assert_raises(Script::Layers::Domain::Errors::ServiceFailureError) { subject }
    end

    it "should raise if the generated wasm binary doesn't exist" do
      ctx
        .expects(:capture2e)
        .once
        .with("cargo build --target=wasm32-unknown-unknown --release")
        .returns(system_output(msg: "", success: true))

      ctx
        .expects(:file_exist?)
        .once
        .with("target/wasm32-unknown-unknown/release/#{script_name}.wasm")
        .returns(false)

      assert_raises(Script::Layers::Infrastructure::Errors::WebAssemblyBinaryNotFoundError) { subject }
    end

    it "should return the compile bytecode" do
      ctx
        .expects(:capture2e)
        .once
        .with("cargo build --target=wasm32-unknown-unknown --release")
        .returns(system_output(msg: "", success: true))

      ctx
        .expects(:file_exist?)
        .once
        .with("target/wasm32-unknown-unknown/release/#{script_name}.wasm")
        .returns(true)

      File
        .expects(:read)
        .once
        .with("target/wasm32-unknown-unknown/release/#{script_name}.wasm")
        .returns("blob")

      assert_equal "blob", subject
    end
  end

  describe ".metadata" do
    subject { rs_task_runner.metadata }

    describe "when metadata file is present and valid" do
      let(:metadata_json) do
        JSON.dump(
          {
            schemaVersions: {
              example: { major: "1", minor: "0" },
            },
          },
        )
      end

      it "should return a proper metadata object" do
        File.expects(:read).with("build/metadata.json").once.returns(metadata_json)

        ctx
          .expects(:file_exist?)
          .with("build/metadata.json")
          .once
          .returns(true)

        assert subject
      end
    end

    describe "when metadata file is missing" do
      it "should raise an exception" do
        assert_raises(Script::Layers::Domain::Errors::MetadataNotFoundError) do
          subject
        end
      end
    end
  end
end
