DRAFTS := $(wildcard drafts/*.md)
PUBLISHED := $(DRAFTS:drafts/%.md=published/%.ptxt)

all: $(PUBLISHED) .git/hooks/pre-commit

drafts/template.md: template.ptxt
	@echo "Creating draft from template"
	src/convert-to-md.sh template.txt drafts/template.md

published/%.ptxt: drafts/%.md
	@echo "Converting $< to $@"
	@mkdir -p $(dir $@)
	src/convert-from-md.sh $< $@

.git/hooks/pre-commit: src/hooks/pre-commit
	@echo "Installing pre-commit hook"
	@cp src/hooks/pre-commit .git/hooks/pre-commit
	@chmod +x .git/hooks/pre-commit
