# frozen_string_literal: true

require "test_helper"

class Flightdeck::ProcessRegistryTest < ActiveSupport::TestCase
  test "groups supervisees under their supervisor" do
    fleet = create_fleet
    registry = Flightdeck::ProcessRegistry.new

    assert_equal 1, registry.tree.size
    root = registry.tree.first

    assert_equal fleet[:supervisor].id, root.id
    assert_equal %w[Dispatcher Scheduler Worker], root.children.map(&:kind).sort
  end

  test "an unsupervised process is listed flat" do
    create_worker(hostname: "web-01", pid: 1290)

    registry = Flightdeck::ProcessRegistry.new

    assert_equal 1, registry.tree.size
    assert_empty registry.tree.first.children
  end

  test "a process whose supervisor row has gone is still listed" do
    supervisor = create_supervisor
    create_worker(supervisor: supervisor)
    supervisor.delete

    registry = Flightdeck::ProcessRegistry.new

    assert_equal 1, registry.tree.size, "an orphan must never be hidden"
    assert_equal "Worker", registry.tree.first.kind
  end

  test "heartbeat freshness follows Solid Queue's own liveness threshold" do
    threshold = SolidQueue.process_alive_threshold
    create_worker(pid: 1, last_heartbeat_at: 2.seconds.ago)
    create_worker(pid: 2, last_heartbeat_at: (threshold * 0.5).ago)
    create_worker(pid: 3, last_heartbeat_at: (threshold + 1.minute).ago)

    by_pid = Flightdeck::ProcessRegistry.new.nodes.index_by(&:pid)

    assert_equal :fresh, by_pid[1].freshness
    assert_equal :stale, by_pid[2].freshness
    assert_equal :dead, by_pid[3].freshness
  end

  test "counts claimed executions per process in one grouped query" do
    worker = create_worker
    other = create_worker(pid: 4173)
    2.times { create_claimed_job(process: worker) }

    by_pid = Flightdeck::ProcessRegistry.new.nodes.index_by(&:pid)

    assert_equal 2, by_pid[worker.pid].claimed_count
    assert_equal 0, by_pid[other.pid].claimed_count
  end

  test "surfaces dead processes and the executions they are still holding" do
    dead = create_worker(pid: 5501, last_heartbeat_at: (SolidQueue.process_alive_threshold + 1.minute).ago)
    create_claimed_job(process: dead)
    create_worker(pid: 4172)

    registry = Flightdeck::ProcessRegistry.new

    assert registry.any_dead?
    assert_equal 1, registry.dead.size
    assert_equal 1, registry.dead_claimed_count
  end

  test "summarises each kind's configuration from its metadata" do
    supervisor = create_supervisor
    create_worker(supervisor: supervisor, queues: "critical,default", threads: 10)
    create_dispatcher(supervisor: supervisor)
    create_scheduler(supervisor: supervisor, task_keys: %w[a b c])

    by_kind = Flightdeck::ProcessRegistry.new.nodes.index_by(&:kind)

    assert_equal "queues: critical,default · 10 threads · every 0.1s", by_kind["Worker"].config_summary
    assert_equal "batch 500 · every 1s", by_kind["Dispatcher"].config_summary
    assert_equal "3 recurring tasks", by_kind["Scheduler"].config_summary
  end

  test "unknown metadata keys are shown rather than dropped" do
    create_process(kind: "Worker", metadata: { "queues" => "*", "experimental_mode" => "on" })

    summary = Flightdeck::ProcessRegistry.new.nodes.first.config_summary

    assert_includes summary, "queues: *"
    assert_includes summary, "experimental_mode: on"
  end

  test "only workers are described as claiming executions" do
    create_supervisor
    create_worker(pid: 4172)

    by_kind = Flightdeck::ProcessRegistry.new.nodes.index_by(&:kind)

    assert by_kind["Worker"].claims_executions?
    refute by_kind["Supervisor"].claims_executions?
  end
end
