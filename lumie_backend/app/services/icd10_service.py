"""ICD-10 code lookup service."""
from typing import List

from ..models.user import ICD10Code, ICD10SearchResult


# Common ICD-10 codes relevant for teens with chronic conditions
# This is a curated subset - in production, use a complete ICD-10 database
ICD10_CODES = [
    # Diabetes
    ICD10Code(code="E10", description="Type 1 diabetes mellitus", category="Endocrine"),
    ICD10Code(code="E10.9", description="Type 1 diabetes mellitus without complications", category="Endocrine"),
    ICD10Code(code="E11", description="Type 2 diabetes mellitus", category="Endocrine"),
    ICD10Code(code="E11.9", description="Type 2 diabetes mellitus without complications", category="Endocrine"),

    # Asthma
    ICD10Code(code="J45", description="Asthma", category="Respiratory"),
    ICD10Code(code="J45.20", description="Mild intermittent asthma", category="Respiratory"),
    ICD10Code(code="J45.30", description="Mild persistent asthma", category="Respiratory"),
    ICD10Code(code="J45.40", description="Moderate persistent asthma", category="Respiratory"),
    ICD10Code(code="J45.50", description="Severe persistent asthma", category="Respiratory"),

    # Cardiovascular
    ICD10Code(code="I10", description="Essential hypertension", category="Cardiovascular"),
    ICD10Code(code="I25", description="Chronic ischemic heart disease", category="Cardiovascular"),
    ICD10Code(code="I42", description="Cardiomyopathy", category="Cardiovascular"),
    ICD10Code(code="I49.9", description="Cardiac arrhythmia, unspecified", category="Cardiovascular"),

    # Chronic Fatigue & Pain
    ICD10Code(code="R53.83", description="Other fatigue", category="General Symptoms"),
    ICD10Code(code="G93.32", description="Myalgic encephalomyelitis/chronic fatigue syndrome", category="Neurological"),
    ICD10Code(code="M79.7", description="Fibromyalgia", category="Musculoskeletal"),
    ICD10Code(code="G43", description="Migraine", category="Neurological"),

    # Autoimmune
    ICD10Code(code="M32", description="Systemic lupus erythematosus", category="Autoimmune"),
    ICD10Code(code="M05", description="Rheumatoid arthritis", category="Autoimmune"),
    ICD10Code(code="K50", description="Crohn's disease", category="Digestive"),
    ICD10Code(code="K51", description="Ulcerative colitis", category="Digestive"),
    ICD10Code(code="E05", description="Thyrotoxicosis (hyperthyroidism)", category="Endocrine"),
    ICD10Code(code="E06.3", description="Autoimmune thyroiditis", category="Endocrine"),

    # Mental Health
    ICD10Code(code="F32", description="Major depressive disorder, single episode", category="Mental Health"),
    ICD10Code(code="F33", description="Major depressive disorder, recurrent", category="Mental Health"),
    ICD10Code(code="F41.1", description="Generalized anxiety disorder", category="Mental Health"),
    ICD10Code(code="F90", description="Attention-deficit hyperactivity disorder", category="Mental Health"),

    # Epilepsy
    ICD10Code(code="G40", description="Epilepsy", category="Neurological"),
    ICD10Code(code="G40.909", description="Epilepsy, unspecified, not intractable", category="Neurological"),

    # Kidney
    ICD10Code(code="N18", description="Chronic kidney disease", category="Renal"),
    ICD10Code(code="N18.3", description="Chronic kidney disease, stage 3", category="Renal"),

    # Cancer/Oncology (survivorship)
    ICD10Code(code="Z85", description="Personal history of malignant neoplasm", category="Oncology"),
    ICD10Code(code="Z85.3", description="Personal history of malignant neoplasm of breast", category="Oncology"),
    ICD10Code(code="Z85.5", description="Personal history of malignant neoplasm of urinary tract", category="Oncology"),

    # Obesity
    ICD10Code(code="E66", description="Overweight and obesity", category="Endocrine"),
    ICD10Code(code="E66.01", description="Morbid obesity due to excess calories", category="Endocrine"),

    # Sickle Cell
    ICD10Code(code="D57", description="Sickle-cell disorders", category="Hematologic"),
    ICD10Code(code="D57.1", description="Sickle-cell disease without crisis", category="Hematologic"),

    # Cystic Fibrosis
    ICD10Code(code="E84", description="Cystic fibrosis", category="Genetic"),
    ICD10Code(code="E84.0", description="Cystic fibrosis with pulmonary manifestations", category="Genetic"),

    # Congenital Heart
    ICD10Code(code="Q20", description="Congenital malformations of cardiac chambers", category="Congenital"),
    ICD10Code(code="Q21", description="Congenital malformations of cardiac septa", category="Congenital"),
    ICD10Code(code="Q24.9", description="Congenital malformation of heart, unspecified", category="Congenital"),

    # Other
    ICD10Code(code="Z96.1", description="Presence of intraocular lens", category="Status"),
    ICD10Code(code="Z95.0", description="Presence of cardiac pacemaker", category="Status"),
]


class ICD10Service:
    """Service for ICD-10 code lookup."""

    def search(self, query: str, limit: int = 20) -> ICD10SearchResult:
        """Search ICD-10 codes by code or description."""
        query_lower = query.lower().strip()

        if not query_lower:
            return ICD10SearchResult(results=[], total=0)

        # Filter codes matching query
        matches = []
        for code in ICD10_CODES:
            if (query_lower in code.code.lower() or
                query_lower in code.description.lower() or
                query_lower in code.category.lower()):
                matches.append(code)

        # Sort by relevance (exact code match first, then by code)
        matches.sort(key=lambda x: (
            not x.code.lower().startswith(query_lower),
            not query_lower in x.description.lower(),
            x.code
        ))

        total = len(matches)
        results = matches[:limit]

        return ICD10SearchResult(results=results, total=total)

    def get_by_code(self, code: str) -> ICD10Code | None:
        """Get a specific ICD-10 code."""
        code_upper = code.upper().strip()
        for icd in ICD10_CODES:
            if icd.code.upper() == code_upper:
                return icd
        return None

    def get_categories(self) -> list[str]:
        """Get all unique categories."""
        categories = set(code.category for code in ICD10_CODES)
        return sorted(list(categories))

    def get_by_category(self, category: str) -> list[ICD10Code]:
        """Get all codes in a category."""
        return [code for code in ICD10_CODES if code.category.lower() == category.lower()]


# Singleton service instance
icd10_service = ICD10Service()
