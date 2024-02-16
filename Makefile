all:
	@echo "Run 'make readme' to generate the README.md file."

make-readme-markdown.el:
	wget -q -O $@ https://raw.github.com/mgalgs/make-readme-markdown/master/make-readme-markdown.el

readme: make-readme-markdown.el
	emacs --script make-readme-markdown.el <real-backup.el >README.md 2>/dev/null

.INTERMEDIATE: make-readme-markdown.el
