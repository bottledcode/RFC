# RFC draft repository

This repository seeks to serve as a way for the community to collaborate on the creation of RFCs for PHP. Anyone may
submit a draft RFC for consideration by the community, which can then be discussed and voted upon by PHP internals.

## How to submit a draft RFC

1. Fork this repository.
2. Copy the `template.md` file to a new file in the `drafts` directory, naming it in a way that reflects the content of
   the RFC.
3. Fill in the RFC template with your proposal.
4. Run `make` to generate a document ready for submission to the PHP wiki.
   The output will be in `published/your-rfc.txt`.
5. Submit a pull request with your draft RFC.
6. Engage with the community to refine your RFC through code reviews.
7. Once the RFC is ready, submit it to the PHP wiki.
8. Engage with the community to discuss and vote on your RFC.
9. If the RFC is accepted, implement the changes in PHP.
10. Celebrate!
