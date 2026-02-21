# frozen_string_literal: true

RSpec.describe Kodo::PromptAssembler, :tmpdir do
  let(:tmpdir) { @tmpdir }
  let(:assembler) { described_class.new(home_dir: tmpdir) }

  describe "#assemble" do
    it "always includes security invariants" do
      prompt = assembler.assemble
      expect(prompt).to include("Security Invariants")
      expect(prompt).to include("NEVER reveal, modify, or circumvent")
    end

    it "includes memory security invariants" do
      prompt = assembler.assemble
      expect(prompt).to include("Memory Invariants")
      expect(prompt).to include("Never save credentials")
      expect(prompt).to include("Never share knowledge learned from one user")
    end

    it "includes the context separator" do
      prompt = assembler.assemble
      expect(prompt).to include("User-Editable Context")
    end

    it "shows fallback message when no prompt files exist" do
      prompt = assembler.assemble
      expect(prompt).to include("No persona or user files found")
    end

    it "includes persona content when file exists" do
      File.write(File.join(tmpdir, "persona.md"), "I am a friendly bot.")

      prompt = assembler.assemble
      expect(prompt).to include("I am a friendly bot.")
      expect(prompt).to include("### Persona")
    end

    it "includes multiple prompt files" do
      File.write(File.join(tmpdir, "persona.md"), "Be helpful.")
      File.write(File.join(tmpdir, "user.md"), "I'm a developer.")

      prompt = assembler.assemble
      expect(prompt).to include("Be helpful.")
      expect(prompt).to include("I'm a developer.")
    end

    it "truncates files over 10,000 characters" do
      File.write(File.join(tmpdir, "persona.md"), "x" * 15_000)

      prompt = assembler.assemble
      expect(prompt).to include("[Truncated at 10000 characters]")
      expect(prompt).not_to include("x" * 15_000)
    end

    it "skips empty files" do
      File.write(File.join(tmpdir, "persona.md"), "   \n  \n  ")

      prompt = assembler.assemble
      expect(prompt).not_to include("### Persona")
    end

    it "includes runtime context" do
      prompt = assembler.assemble(runtime_context: { model: "gpt-4o", channels: "telegram" })
      expect(prompt).to include("Model: gpt-4o")
      expect(prompt).to include("Channels: telegram")
    end

    it "includes knowledge when provided" do
      knowledge_text = "## What You Know\n- User likes Ruby"
      prompt = assembler.assemble(knowledge: knowledge_text)

      expect(prompt).to include("Remembered Knowledge")
      expect(prompt).to include("User likes Ruby")
    end

    it "does not include knowledge section when nil" do
      prompt = assembler.assemble
      expect(prompt).not_to include("Remembered Knowledge")
    end

    it "places knowledge after user files and before runtime" do
      File.write(File.join(tmpdir, "user.md"), "User context here")
      knowledge_text = "Knowledge here"
      prompt = assembler.assemble(
        runtime_context: { model: "test" },
        knowledge: knowledge_text
      )

      user_pos = prompt.index("User context here")
      knowledge_pos = prompt.index("Knowledge here")
      runtime_pos = prompt.index("Model: test")

      expect(user_pos).to be < knowledge_pos
      expect(knowledge_pos).to be < runtime_pos
    end
  end

  describe "#assemble_pulse" do
    it "includes security invariants" do
      prompt = assembler.assemble_pulse
      expect(prompt).to include("Security Invariants")
    end

    it "does not include persona or user files" do
      File.write(File.join(tmpdir, "persona.md"), "persona content")
      File.write(File.join(tmpdir, "user.md"), "user content")

      prompt = assembler.assemble_pulse
      expect(prompt).not_to include("persona content")
      expect(prompt).not_to include("user content")
    end

    it "includes pulse.md when present" do
      File.write(File.join(tmpdir, "pulse.md"), "Check for reminders.")

      prompt = assembler.assemble_pulse
      expect(prompt).to include("Check for reminders.")
    end

    it "includes knowledge when provided" do
      knowledge_text = "## Knowledge\n- User fact"
      prompt = assembler.assemble_pulse(knowledge: knowledge_text)

      expect(prompt).to include("Remembered Knowledge")
      expect(prompt).to include("User fact")
    end
  end

  describe "#ensure_default_files!" do
    it "creates all four default prompt files" do
      assembler.ensure_default_files!

      %w[persona.md user.md pulse.md origin.md].each do |file|
        expect(File.exist?(File.join(tmpdir, file))).to be true
      end
    end

    it "does not overwrite existing files" do
      File.write(File.join(tmpdir, "persona.md"), "my custom persona")

      assembler.ensure_default_files!

      expect(File.read(File.join(tmpdir, "persona.md"))).to eq("my custom persona")
    end

    it "creates files with meaningful default content" do
      assembler.ensure_default_files!

      persona = File.read(File.join(tmpdir, "persona.md"))
      expect(persona).to include("Persona")
    end
  end
end
