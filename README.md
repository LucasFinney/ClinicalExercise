Progress:
3/19/2024
- Wrote a small macro script to convert .XPT files into SAS data files for convenience (DataSetImport.sas in the prod_code folder) 
- Began work on ADSL dataset (prod_code/ADSL.sas) -> Identified all variables which can be directly copied from the DM dataset

3/20/2024
- Began work on deriving variables based on existing variables. See commit log for details.
- Note -> Need to make sure dates are in the correct format.

3/21/2024
- Refactored code
- Determined which subjects completed the entire protocol and which subjects withdrew early (needed for determining TRTEDT)
- Properly formatted TRTSDT, TRTEDT, and derived TRTDURD according to specs

(Missing Logs... whoops)

4/1/2024
- Spent all day finishing the ADSL set.
