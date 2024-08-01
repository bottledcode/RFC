DRAFTS := $(wildcard drafts/*.md)
PUBLISHED := $(DRAFTS:drafts/%.md=published/%.txt)

all: $(PUBLISHED)

drafts/template.md: template.txt
	@echo "Creating draft from template"
	src/convert-to-md.sh template.txt drafts/template.md

published/%.txt: drafts/%.md
	@echo "Converting $< to $@"
	@mkdir -p $(dir $@)
	src/convert-from-md.sh $< $@
