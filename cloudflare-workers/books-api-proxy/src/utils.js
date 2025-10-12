export function advancedDeduplication(works) {
    if (!works || works.length <= 1) return works;

    const dedupedWorks = [];
    const seenKeys = new Set();

    for (const work of works) {
        const title = (work.title || '').toLowerCase()
            .replace(/[^\w\s]/g, '')
            .replace(/\s+/g, ' ')
            .trim();

        const authors = Array.isArray(work.authors)
            ? work.authors.map(a => (typeof a === 'string' ? a : a.name || '').toLowerCase()).join(',')
            : '';

        const normalizedKey = `${authors}:${title}`;

        let isDuplicate = false;
        for (const existingKey of seenKeys) {
            if (calculateSimilarity(normalizedKey, existingKey) > 0.9) {
                isDuplicate = true;
                break;
            }
        }

        if (!isDuplicate) {
            seenKeys.add(normalizedKey);
            dedupedWorks.push(work);
        }
    }

    return dedupedWorks;
}

export function calculateSimilarity(str1, str2) {
    const set1 = new Set(str1.toLowerCase().split(/\s+/));
    const set2 = new Set(str2.toLowerCase().split(/\s+/));

    const intersection = new Set([...set1].filter(x => set2.has(x)));
    const union = new Set([...set1, ...set2]);

    return intersection.size / union.size;
}

export function isLikelyAuthorQuery(query) {
    const cleanQuery = query.toLowerCase().trim();

    const authorIndicators = [
        /^[a-z]+\s+[a-z]+$/,
        /^[a-z]+\s+[a-z]\.\s+[a-z]+$/,
        /^[a-z]+,\s+[a-z]+$/,
        /^[a-z]+\s+[a-z]+\s+[a-z]+$/,
    ];

    const titleIndicators = [
        /^the\s+/,
        /^a\s+/,
        /^an\s+/,
        /\d/,
        /:/,
        /series$/,
        /book$/,
        /novel$/,
    ];

    for (const pattern of titleIndicators) {
        if (pattern.test(cleanQuery)) {
            return false;
        }
    }

    for (const pattern of authorIndicators) {
        if (pattern.test(cleanQuery)) {
            return true;
        }
    }

    const words = cleanQuery.split(/\s+/);
    if (words.length === 2 && words.every(word => /^[a-z]+$/.test(word))) {
        return true;
    }

    return false;
}
