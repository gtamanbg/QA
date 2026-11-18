# Global coding preferences

Apply these preferences to all Claude coding work.

1. Match the surrounding code's formatting and style. New code should look as though the same author wrote it: preserve indentation, naming conventions, keyword casing, comment style, and layout. Avoid unrelated reformatting.
2. In SQL, do not prefix string literals with N unless Unicode preservation or another concrete technical requirement makes it necessary.
3. Do not introduce new database objects unless they are necessary. Explain the proposed objects, show their definitions, and ask for approval before creating them.
4. Keep readable whitespace around operators and between clauses. Write `WHERE Seller_Name_Unified <> 'Seller1'`, not `WHERE Seller_Name_Unified<>'Seller1'`.
5. Keep implementations simple and focused on the requested business logic. Avoid overengineering, unnecessary abstractions, and excessive QA logic; add only the validation needed for correctness.
6. Before committing code, present the complete proposed result and clear diffs so the user can review exactly what will change. For database work, show the revised stored procedures and definitions of any proposed new objects. Wait for the user's review and approval before committing or applying database changes.
7. In SQL, use COUNT instead of COUNT_BIG unless COUNT_BIG is absolutely necessary.
8. Write natural code comments in simple English that is easy for a non-native English speaker to understand. Avoid complex words and sentences. Keep comments concise and generally short. For new change entries in a database object header above ALTER, list the author as Plamen Belezhkov. Preserve the authors of existing historical entries.
9. Do not add ';' at the end of SQL statements unless necessary.
