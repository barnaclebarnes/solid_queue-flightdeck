# frozen_string_literal: true

require "test_helper"

class Flightdeck::ArgumentsPreviewTest < ActiveSupport::TestCase
  Preview = Flightdeck::ArgumentsPreview

  test "shows the job's own arguments rather than the ActiveJob envelope" do
    payload = {
      "job_class" => "SearchIndexJob",
      "job_id" => "b9f1c2d3-0000-4444-8888-aaaabbbbcccc",
      "queue_name" => "default",
      "priority" => nil,
      "arguments" => [ { "model" => "Product", "id" => 41_230 } ],
      "executions" => 0
    }.to_json

    result = Preview.format(payload)

    assert_equal %([{"model":"Product","id":41230}]), result
    refute_includes result, "job_class"
    refute_includes result, "b9f1c2d3"
  end

  test "recovers the arguments from a payload truncated mid-array" do
    payload = %({"job_class":"SyncInventoryJob","job_id":"abc","arguments":[{"warehouse":"yul-1","sku_ba)

    result = Preview.format(payload)

    assert result.start_with?(%([{"warehouse":"yul-1")), result
    refute_includes result, "job_class"
    assert result.end_with?("…"), "a truncated value should say so"
  end

  test "stops at the end of the arguments value when more keys follow" do
    payload = %({"arguments":[1,2,3],"executions":2,"locale":"en"})

    assert_equal "[1,2,3]", Preview.format(payload)
  end

  test "handles strings containing braces and escaped quotes" do
    payload = { "arguments" => [ "a}{b", %(quote " inside), "[]" ] }.to_json

    assert_equal %(["a}{b","quote \\" inside","[]"]), Preview.format(payload)
  end

  test "falls back to the raw prefix when the arguments key was cut off entirely" do
    payload = %({"job_class":"AVeryLongJobClassNameThatUsesUpTheWholePrefix","job_id":"abc)

    result = Preview.format(payload)

    assert_includes result, "AVeryLongJobClassName"
  end

  test "handles payloads that are not the ActiveJob shape at all" do
    assert_equal "[1,2]", Preview.format("[1,2]")
    assert_equal "", Preview.format(nil)
    assert_equal "", Preview.format("")
  end

  test "collapses whitespace and truncates to the requested length" do
    payload = { "arguments" => [ "x" * 400 ] }.to_json

    result = Preview.format(payload, length: 40)

    assert_equal 40, result.length
    assert result.end_with?("…")
  end

  test "an empty arguments array reads as empty rather than as boilerplate" do
    assert_equal "[]", Preview.format({ "job_class" => "NoArgsJob", "arguments" => [] }.to_json)
  end

  test "list rows show arguments, not the envelope" do
    create_ready_job(class_name: "SearchIndexJob",
                     arguments: { "arguments" => [ { "model" => "Product", "id" => 41_230 } ] })

    preview = Flightdeck::JobsQuery.new(state: :ready).rows.first.args_preview

    assert_equal %([{"model":"Product","id":41230}]), Preview.format(preview)
  end

  test "the SQL prefix is wide enough to reach the arguments of a realistic payload" do
    create_ready_job(class_name: "Billing::ChargeSubscriptionJob",
                     arguments: { "arguments" => [ { "subscription_id" => 48_211, "attempt" => 3 } ] })

    preview = Flightdeck::JobsQuery.new(state: :ready).rows.first.args_preview

    assert_includes preview, %("arguments"),
                    "ARGUMENTS_PREVIEW_BYTES must cover the envelope that precedes the arguments"
    assert_includes Preview.format(preview), "subscription_id"
  end
end
